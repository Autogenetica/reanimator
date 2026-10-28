# frozen_string_literal: true

require "time"

module Reanimator
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
  #
  # Execution has a third gate: the security posture's network rule
  # ({EgressControl}). A posture that denies egress either runs every command
  # in an empty network namespace or refuses to execute - never unprotected.
  class BaselineRunner
    attr_reader :contract, :execute, :timeout

    def initialize(contract, execute: false, timeout: nil, now: nil)
      @contract = contract
      @execute = execute
      @timeout = timeout || Reanimator.configuration.command_timeout
      @now = now
    end

    # @return [Baseline]
    def run
      if executing?
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
          timeout: timeout, execution_root: execution_root, egress: egress
        ).call
      end
      results = apply_waivers(results)

      Baseline.new(
        contract: contract,
        results: results,
        state: ProofOfLife.assess(contract, results),
        generated_at: now,
        executed: executing?,
        egress: egress
      )
    end

    # Re-tags an unresolved required criterion as accepted risk when an active
    # waiver covers it (section 09). The waiver does not make it verified - it
    # records the failure as explicitly accepted, so it stops blocking the
    # repository state while staying visible.
    def apply_waivers(results)
      results.map do |result|
        next result unless result.waivable?

        waiver = contract.waiver_for(result.criterion.id)
        waiver ? result.accepted_via(waiver) : result
      end
    end

    # Execution requires both the per-run request and the global allowance.
    # Native evaluators ignore this flag and always inspect.
    def execution_allowed?
      Reanimator.configuration.execution_permitted?(execute)
    end

    # Whether commands actually run: execution is allowed and the posture's
    # network rule can be honored on this host.
    def executing?
      execution_allowed? && !egress.refused?
    end

    # Only decided when execution is requested, so a read-only baseline never
    # probes the host for namespace support.
    def egress
      return unless execution_allowed?

      @egress ||= EgressControl.for(contract.security_posture)
    end

    def now
      @now || Time.now
    end
  end
end
