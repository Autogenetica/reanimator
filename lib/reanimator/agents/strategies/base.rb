# frozen_string_literal: true

module Reanimator
  module Agents
    # Repair strategies for the local, rule-based agent. A "local agent" is a
    # first-class provider in the specification (section 01: "Support Codex,
    # Claude, Amp, local agents, and future providers"). Each strategy is a
    # deterministic, no-network fixer that inspects a workspace and, when it
    # recognizes a defect, proposes a plan and a patch.
    module Strategies
      class Base
        # @param task [RepairTask]
        # @return [Boolean] whether this strategy recognizes the defect
        def applies?(task)
          raise NotImplementedError, "#{self.class} must implement #applies?"
        end

        # @param task [RepairTask]
        # @return [Array(String, Patch)] a plan and a patch
        def call(task)
          raise NotImplementedError, "#{self.class} must implement #call"
        end
      end
    end
  end
end
