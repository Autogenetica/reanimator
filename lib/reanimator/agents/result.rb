# frozen_string_literal: true

module Reanimator
  module Agents
    # What an adapter returns from a repair attempt (specification section 08
    # commissioning steps 3 and 5, section 17 run ledger). A result is an
    # untrusted *proposal*: a structured plan, a patch expressed as data, and
    # the observable cost/latency/tool-use/network the harness records. It is
    # never a verdict - Reanimator computes pass/fail itself.
    class Result
      attr_reader :plan, :patch, :cost_usd, :latency_s, :tool_use, :network, :message

      def initialize(plan: nil, patch: Patch.new, cost_usd: 0.0, latency_s: 0.0,
        tool_use: [], network: [], message: nil)
        @plan = plan
        @patch = patch
        @cost_usd = cost_usd
        @latency_s = latency_s
        @tool_use = tool_use
        @network = network
        @message = message
      end

      # A well-formed repair proposal has both a structured plan and a
      # non-empty patch (section 08 step 3: "require a structured plan and
      # patch").
      def structured? = !plan.to_s.strip.empty? && !patch.empty?

      def to_h
        {
          plan: plan,
          patch: patch.to_h,
          cost_usd: cost_usd,
          latency_s: latency_s,
          tool_use: tool_use,
          network: network,
          message: message
        }.compact
      end
    end
  end
end
