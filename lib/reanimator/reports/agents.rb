# frozen_string_literal: true

module Reanimator
  module Reports
    # Lists coding-agent adapters and whether each is available right now
    # (specification section 08). Hosted providers report themselves unavailable
    # with a reason until connected, so the surface is honest about what can
    # actually run.
    class Agents
      def initialize(adapters)
        @adapters = adapters
      end

      def render
        (["Coding agents:"] + @adapters.map { |adapter| line(adapter) }).join("\n")
      end

      private

      def line(adapter)
        status = adapter.available? ? "available" : "unavailable"
        detail = adapter.available? ? "" : " — #{adapter.unavailable_reason}"
        "  #{Reports.glyph(adapter.available? ? :verified : :skipped)} #{adapter.provider} " \
          "(#{status}) [#{adapter.capabilities.join(", ")}]#{detail}"
      end
    end
  end
end
