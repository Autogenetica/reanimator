# frozen_string_literal: true

module Reanimator
  module Agents
    # The immutable objective handed to an agent for one repair (specification
    # section 08 fallback rules and section 17 run ledger). Everything here is
    # frozen: the agent receives the original task, the constraints it may not
    # exceed, and *verified evidence* - never mutable conclusions it could talk
    # itself out of. A fallback agent receives this very same object, not the
    # previous agent's narrative.
    class RepairTask
      # @return [AcceptanceCriterion] the failing criterion to satisfy
      attr_reader :objective
      # @return [String] absolute path to the agent's isolated workspace copy
      attr_reader :workspace
      # @return [Constraints] the immutable envelope this repair must stay
      #   inside (allowed paths, protected paths, budget, code egress)
      attr_reader :constraints
      # @return [Baseline] the verified pre-repair evidence
      attr_reader :evidence

      def initialize(objective:, workspace:, evidence:, constraints: {})
        @objective = objective
        @workspace = workspace
        @evidence = evidence
        @constraints = Constraints.from(constraints)
        freeze
      end

      # @return [String] a plain-language statement of the goal
      def goal = objective.claim

      # --- read-only workspace access for adapters -----------------------------

      def read(relative)
        full = File.join(workspace, relative)
        File.read(full) if File.file?(full)
      end

      def glob(pattern)
        Dir.glob(File.join(workspace, pattern))
          .map { |absolute| absolute.delete_prefix("#{workspace}/") }
          .sort
      end

      # Whether a path is inside the constraints' allowed set (and outside the
      # protected set). Adapters should honor this; the harness enforces it.
      def may_edit?(path) = constraints.may_edit?(path)
    end
  end
end
