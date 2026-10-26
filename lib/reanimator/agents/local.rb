# frozen_string_literal: true

module Reanimator
  module Agents
    # The reference local agent: deterministic, no network, always available.
    # It runs a list of rule-based {Strategies} and proposes the first patch
    # that matches. Because it never reaches the network and keeps code on the
    # user's runner, it satisfies the "local" security posture (section 12) and
    # is the adapter commissioning can always prove end to end.
    class Local < Adapter
      DEFAULT_STRATEGIES = [Strategies::ArithmeticFix].freeze

      def initialize(connection, strategies: nil)
        super(connection)
        @strategies = strategies || DEFAULT_STRATEGIES.map(&:new)
      end

      def available? = true

      # Local execution never touches the network by design.
      def capabilities
        [Capability::PLAN, Capability::PATCH, Capability::REPOSITORY_EDIT, Capability::SANDBOX_EXEC]
      end

      def repair(task)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        strategy = @strategies.find { |s| s.applies?(task) }

        if strategy
          plan, patch = strategy.call(task)
          Result.new(plan: plan, patch: patch, cost_usd: 0.0,
            latency_s: elapsed(started), tool_use: [Capability::REPOSITORY_EDIT, Capability::PATCH], network: [])
        else
          Result.new(plan: nil, patch: Patch.new, cost_usd: 0.0, latency_s: elapsed(started),
            message: "No local strategy matched the objective #{task.objective.id.inspect}.")
        end
      end

      private

      def elapsed(started)
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3)
      end
    end
  end
end
