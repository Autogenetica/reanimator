# frozen_string_literal: true

require "time"

module Frankenstein
  # Executes a baseline for one repository against its effective contract
  # (specification section 14). Every criterion is graded by an isolated
  # evaluator; the runner itself never edits the repository. Execution is
  # opt-in and doubly gated - by the per-run `execute` flag and by the global
  # `allow_execution` configuration - so the default really is read-only, and
  # even when executing, native (inspection-only) evaluators still run.
  #
  # When commands do execute, they run in a *disposable copy* of the repository,
  # never the original working tree (section 14: "all commands run in a
  # disposable workspace" and "the baseline is read-only with respect to
  # repository source"). Inspection-only evaluators still read the original.
  class BaselineRunner
    attr_reader :contract, :execute, :timeout

    def initialize(contract, execute: false, timeout: nil, now: nil)
      @contract = contract
      @execute = execute
      @timeout = timeout || Frankenstein.configuration.command_timeout
      @now = now
    end

    # @return [Baseline]
    def run
      if execution_allowed?
        # Commands run inside a throwaway copy so builds/tests cannot mutate the
        # real checkout (no stray .gem, coverage/, or tmp/ artifacts).
        Isolation.copy(contract.repository.path) { |workspace| measure(workspace) }
      else
        measure(contract.repository.path)
      end
    end

    private

    def measure(execution_root)
      results = contract.criteria.map do |criterion|
        Evaluators.for(
          criterion, contract: contract, execute: execution_allowed?,
          timeout: timeout, execution_root: execution_root
        ).call
      end
      results = apply_waivers(results)

      Baseline.new(
        contract: contract,
        results: results,
        state: ProofOfLife.assess(contract, results),
        generated_at: now,
        executed: execution_allowed?
      )
    end

    # Re-tags an unresolved required criterion as accepted risk when an active
    # waiver covers it (section 09). The waiver does not make it verified - it
    # records the failure as explicitly accepted, so it stops blocking the
    # repository state while staying visible.
    def apply_waivers(results)
      results.map do |result|
        next result unless result.required? && !result.verified? && !result.accepted_risk?

        waiver = contract.waiver_for(result.criterion.id)
        next result unless waiver

        CriterionResult.new(
          criterion: result.criterion, status: :accepted_risk,
          detail: waiver_detail(waiver, result), evidence: result.evidence, duration: result.duration
        )
      end
    end

    def waiver_detail(waiver, result)
      bound = waiver.expires ? " until #{waiver.expires.strftime("%Y-%m-%d")}" : ""
      "Accepted risk#{bound}: #{waiver.reason} (was #{result.status})"
    end

    # Execution requires both the per-run request and the global allowance.
    # Native evaluators ignore this flag and always inspect.
    def execution_allowed?
      execute && Frankenstein.configuration.allow_execution
    end

    def now
      @now || Time.now
    end
  end
end
