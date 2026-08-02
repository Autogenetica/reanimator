# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module Frankenstein
  module Commissioning
    # Runs the six-step commissioning test from specification section 08:
    # validate credentials and capabilities, run a synthetic repair against a
    # disposable fixture, require a structured plan and patch, evaluate the
    # result *independently*, report the observable cost/latency/tools/network,
    # and mark the profile ready/degraded/incompatible/unavailable.
    #
    # Verifier isolation (section 09) is structural here: the agent works in its
    # own copy and returns a patch as data; the harness applies that patch to a
    # *separate, clean* copy and grades it with Frankenstein's own evaluators.
    # A patch that reaches for a protected or verifier path is refused - the
    # anti-gaming rule, enforced.
    class Test
      ALLOWED_EDIT_PATHS = ["lib/**", "*.rb"].freeze

      def initialize(adapter, fixture: Fixture)
        @adapter = adapter
        @fixture = fixture
      end

      # @return [Commissioning::Report]
      def run
        return unavailable unless @adapter.available?

        fixture_path = @fixture.build
        scratch = [fixture_path]
        begin
          contract = contract_for(fixture_path)
          pre = BaselineRunner.new(contract, execute: true).run
          objective = pre.results.find { |r| r.required? && r.failed? }&.criterion
          return incompatible("The fixture did not present a failing required objective.", pre: pre) unless objective

          workspace = copy(fixture_path, scratch)
          result = @adapter.repair(build_task(objective, workspace, contract, pre))
          return incompatible("The agent returned no structured plan and patch.", pre: pre, result: result) unless result.structured?

          if (violation = protected_violation(build_task(objective, workspace, contract, pre), result))
            return incompatible(violation, pre: pre, result: result)
          end

          eval_dir = copy(fixture_path, scratch)
          result.patch.apply(eval_dir)
          post = BaselineRunner.new(contract_for(eval_dir), execute: true).run

          verdict(objective, pre, post, result)
        ensure
          scratch.each { |dir| FileUtils.remove_entry(dir, true) }
        end
      end

      private

      def contract_for(path)
        EffectivePolicyResolver.new(Repository.at(path)).resolve
      end

      def build_task(objective, workspace, contract, pre)
        Agents::RepairTask.new(
          objective: objective, workspace: workspace, evidence: pre,
          constraints: {
            allowed_paths: ALLOWED_EDIT_PATHS,
            protected_paths: contract.protected_paths,
            max_cost_usd: @adapter.connection.max_cost_usd,
            code_egress: @adapter.code_egress
          }
        )
      end

      # Anti-gaming (section 09): a repair may not edit a protected or
      # out-of-scope path. This is what stops a task from rewriting the rules of
      # proof and then passing under the new rules.
      def protected_violation(task, result)
        bad = result.patch.paths.reject { |path| task.may_edit?(path) }
        "The patch attempted to edit protected or out-of-scope paths: #{bad.join(", ")}." unless bad.empty?
      end

      def verdict(objective, pre, post, result)
        target = post.results.find { |r| r.criterion.id == objective.id }
        regressions = regressed(pre, post)
        over_budget = result.cost_usd > @adapter.connection.max_cost_usd

        if target&.verified? && regressions.empty? && !over_budget
          report(:ready, pre: pre, post: post, result: result, objective: objective)
        else
          report(:degraded, pre: pre, post: post, result: result, objective: objective,
            reason: degraded_reason(target, regressions, over_budget))
        end
      end

      # Required criteria that were verified before the repair but are not
      # after it - genuine regressions the patch must not introduce.
      def regressed(pre, post)
        proven = pre.results.select { |r| r.required? && r.verified? }.map { |r| r.criterion.id }
        post.results.select { |r| proven.include?(r.criterion.id) && !r.verified? }.map { |r| r.criterion.id }
      end

      def degraded_reason(target, regressions, over_budget)
        if target.nil? || !target.verified?
          "The patch did not resolve the objective."
        elsif over_budget
          "The repair exceeded the connection budget."
        else
          "The repair regressed: #{regressions.join(", ")}."
        end
      end

      def copy(source, scratch)
        destination = Dir.mktmpdir("frankenstein-ws")
        FileUtils.cp_r(File.join(source, "."), destination)
        scratch << destination
        destination
      end

      def unavailable
        report(:unavailable, reason: @adapter.unavailable_reason)
      end

      def incompatible(reason, **rest)
        report(:incompatible, reason: reason, **rest)
      end

      def report(readiness, pre: nil, post: nil, result: nil, objective: nil, reason: nil)
        Report.new(
          provider: @adapter.provider,
          readiness: readiness,
          reason: reason,
          capabilities: @adapter.capabilities,
          objective: objective&.id,
          pre_state: pre&.state&.to_sym,
          post_state: post&.state&.to_sym,
          cost_usd: result&.cost_usd || 0.0,
          latency_s: result&.latency_s || 0.0,
          tool_use: result&.tool_use || [],
          network: result&.network || []
        )
      end
    end
  end
end
