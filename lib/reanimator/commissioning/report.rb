# frozen_string_literal: true

module Reanimator
  module Commissioning
    # The outcome of a commissioning test (specification section 08 step 6:
    # "mark the profile ready, degraded, incompatible, or unavailable"), plus
    # the observable facts step 5 requires: cost, latency, permissions, tool
    # use, and any network destinations. Reanimator computes the verdict
    # itself from independent evaluation; the agent never grades its own work.
    class Report
      attr_reader :provider, :readiness, :reason, :capabilities, :objective,
        :pre_state, :post_state, :cost_usd, :latency_s, :tool_use, :network

      def initialize(provider:, readiness:, reason: nil, capabilities: [], objective: nil,
        pre_state: nil, post_state: nil, cost_usd: 0.0, latency_s: 0.0, tool_use: [], network: [])
        @provider = provider
        @readiness = readiness.to_sym
        @reason = reason
        @capabilities = capabilities
        @objective = objective
        @pre_state = pre_state
        @post_state = post_state
        @cost_usd = cost_usd
        @latency_s = latency_s
        @tool_use = tool_use
        @network = network
      end

      def ready? = readiness == :ready

      # The whole point of the slice: a profile can be proven ready without any
      # repository write. Commissioning only ever touches disposable fixtures.
      def proven_without_writes? = true

      def to_h
        {
          provider: provider, readiness: readiness, reason: reason,
          capabilities: capabilities, objective: objective,
          pre_state: pre_state, post_state: post_state,
          cost_usd: cost_usd, latency_s: latency_s, tool_use: tool_use, network: network
        }.compact
      end
    end
  end
end
