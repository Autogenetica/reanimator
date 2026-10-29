# frozen_string_literal: true

require "fileutils"

module Reanimator
  # Orchestrates one bounded repair, end to end, without writing to the
  # repository (specification section 11 repair rung, section 17 run). The flow
  # is: baseline to find a failing obligation, check the permission model,
  # route to a ready agent, let it propose a patch in an isolated workspace,
  # apply that patch to a *separate* clean copy, re-evaluate independently, and
  # only then materialize a proposed draft PR. Every exit is a recorded {Run}.
  class RepairRun
    REQUIRED_CAPABILITIES = [Agents::Capability::PATCH, Agents::Capability::REPOSITORY_EDIT].freeze
    EDITABLE = ["lib/**", "app/**", "*.rb"].freeze

    def initialize(contract, provider: :local, task_class: :patch_dependency, trigger: "user request")
      @contract = contract
      @provider = provider.to_sym
      @task_class = task_class.to_sym
      @trigger = trigger
    end

    # @return [Run]
    def run
      pre = BaselineRunner.new(@contract, execute: true).run
      # A baseline that never ran has no failures to find; reading that as
      # "all required criteria pass" would turn a refusal into a clean bill.
      return record(:safe_stop, pre: pre, reason: unexecuted_reason(pre)) unless pre.executed?

      target = pre.first_failing_required_criterion
      return record(:no_op, pre: pre, reason: "All required criteria pass; no repair is needed.") unless target

      resolution = PermissionModel.new(@contract).resolve(@task_class)
      unless resolution.permits?(:repair)
        return record(:escalation, pre: pre, objective: target,
          reason: "Repair is not enabled for #{@task_class} (max autonomy #{resolution.max_action}); enable repair to proceed.")
      end

      decision = route
      unless decision.selected?
        return record(:safe_stop, pre: pre, objective: target, reason: "No ready agent. #{decision.explanation}")
      end

      attempt(pre, target, decision.profile)
    end

    private

    def attempt(pre, target, profile)
      adapter = Agents.for(profile.connection)
      workspace = Isolation.copy(@contract.repository.path)
      begin
        task = build_task(target, workspace, pre)
        result = adapter.repair(task)
        unless result.structured?
          return record(:safe_stop, pre: pre, objective: target, provider: adapter.provider,
            reason: result.message || "The agent produced no structured plan and patch.")
        end

        breach = result.patch.paths.reject { |path| task.may_edit?(path) }
        unless breach.empty?
          return record(:escalation, pre: pre, objective: target, provider: adapter.provider,
            reason: "Refused: the patch touches protected or out-of-scope paths: #{breach.join(", ")}.")
        end

        verify(pre, target, adapter, result)
      ensure
        FileUtils.remove_entry(workspace, true)
      end
    end

    def verify(pre, target, adapter, result)
      post = evaluate_isolated(result.patch)
      if resolved?(target, pre, post)
        change = ProposedChange.new(
          obligation: obligation(target), patch: result.patch, plan: result.plan,
          pre_state: pre.state.to_sym, post_state: post.state.to_sym
        )
        record(:draft_pr, pre: pre, post: post, objective: target, provider: adapter.provider,
          proposed_change: change, cost: result.cost_usd, tools: result.tool_use)
      else
        record(:report, pre: pre, post: post, objective: target, provider: adapter.provider,
          cost: result.cost_usd, reason: "The repair did not independently verify; not proposing a change.")
      end
    end

    # Apply the patch to a fresh, clean copy and grade it there - never in the
    # agent's workspace (verifier isolation, section 09).
    def evaluate_isolated(patch)
      Isolation.copy(@contract.repository.path) do |eval_dir|
        patch.apply(eval_dir)
        BaselineRunner.new(EffectivePolicyResolver.new(Repository.at(eval_dir)).resolve, execute: true).run
      end
    end

    def unexecuted_reason(pre)
      why = pre.execution_refused? ? pre.egress.reason : "execution is disabled (allow_execution is false)"
      "Repair needs an executed baseline, and none ran: #{why}."
    end

    def resolved?(target, pre, post)
      return false unless post.result_for(target.id)&.verified?

      # No criterion that was verified-required before may be unresolved after.
      regressed = pre.verified_required_ids & post.unresolved_required.map { |r| r.criterion.id }
      regressed.empty?
    end

    # Readiness is *proven*, not assumed: the provider is commissioned against a
    # disposable fixture and its verdict (ready/degraded/incompatible/unavailable)
    # decides eligibility. Only a commissioned-ready provider is routed to; any
    # other verdict fails closed to a safe stop.
    def route
      adapter = Agents.for(connection)
      readiness = Commissioning::Test.new(adapter).run.readiness
      profile = AgentProfile.from_adapter(adapter, readiness: readiness)
      Routing::Router.new([profile]).select(required_capabilities: REQUIRED_CAPABILITIES, task_class: @task_class)
    end

    def build_task(target, workspace, pre)
      Agents::RepairTask.new(
        objective: target, workspace: workspace, evidence: pre,
        constraints: Agents::Constraints.new(
          allowed_paths: EDITABLE, protected_paths: @contract.protected_paths,
          max_cost_usd: connection.max_cost_usd, code_egress: Agents.for(connection).code_egress
        )
      )
    end

    def obligation(target)
      Obligation.new(
        repository: @contract.repository, policy_version: @contract.policy_version,
        target: target, trigger: @trigger, task_class: @task_class
      )
    end

    def connection
      @connection ||=
        if @provider == :local
          AgentConnection.local
        else
          AgentConnection.new(provider: @provider, credentials_ref: Reanimator::CREDENTIAL_REFS[@provider])
        end
    end

    def record(outcome, pre: nil, post: nil, objective: nil, provider: nil, proposed_change: nil, cost: 0.0, tools: [], reason: nil)
      Run.new(
        outcome: outcome, repository: @contract.repository, policy_version: @contract.policy_version,
        trigger: @trigger, objective: objective, provider: provider, access: {tools: tools},
        pre_state: pre&.state&.to_sym, post_state: post&.state&.to_sym,
        cost_usd: cost, proposed_change: proposed_change, reason: reason
      )
    end
  end
end
