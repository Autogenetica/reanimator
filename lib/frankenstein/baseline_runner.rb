# frozen_string_literal: true

require "time"

module Frankenstein
  # Executes a baseline for one repository against its effective contract
  # (specification section 14). Every criterion is graded by an isolated
  # evaluator; the runner itself never edits the repository. Execution is
  # opt-in and doubly gated - by the per-run `execute` flag and by the global
  # `allow_execution` configuration - so the default really is read-only, and
  # even when executing, native (inspection-only) evaluators still run.
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
      results = contract.criteria.map do |criterion|
        Evaluators.for(criterion, contract: contract, execute: execution_allowed?, timeout: timeout).call
      end

      Baseline.new(
        contract: contract,
        results: results,
        state: ProofOfLife.assess(contract, results),
        generated_at: now,
        executed: execution_allowed?
      )
    end

    private

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
