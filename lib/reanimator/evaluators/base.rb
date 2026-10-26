# frozen_string_literal: true

module Reanimator
  module Evaluators
    # Shared plumbing for evaluators. Subclasses implement {#call} and return a
    # {CriterionResult}. The evaluator sees the repository and discovery only
    # through the read-only effective contract - it never receives, and cannot
    # reach, a mutable agent workspace.
    class Base
      attr_reader :criterion, :contract, :execute, :timeout, :execution_root

      def initialize(criterion, contract:, execute:, timeout:, execution_root: nil)
        @criterion = criterion
        @contract = contract
        @execute = execute
        @timeout = timeout
        @execution_root = execution_root || contract.repository.path
      end

      # @return [CriterionResult]
      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      private

      def repository = contract.repository

      def discovery = contract.discovery

      def result(status, detail: nil, evidence: nil, duration: nil)
        CriterionResult.new(
          criterion: criterion, status: status, detail: detail, evidence: evidence, duration: duration
        )
      end

      # Keep only the tail of noisy command output as retained evidence.
      def tail(text, limit: 1_500)
        stripped = text.to_s.strip
        return stripped if stripped.length <= limit

        "...#{stripped[-limit..]}"
      end
    end

    # Fallback for a criterion whose evaluator is not available in the
    # read-only baseline (for example a hosted GitHub check). It is honest
    # about the gap rather than guessing.
    class Unsupported < Base
      def call
        result(:skipped, detail: "Evaluator #{criterion.evaluator.inspect} is not available in a read-only baseline.")
      end
    end
  end
end
