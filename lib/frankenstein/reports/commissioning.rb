# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders a commissioning report (specification section 08). It states the
    # readiness verdict, the objective's before/after state, and the observable
    # cost/latency/tools/network - and closes by affirming the slice's promise:
    # a profile was proven ready without any repository write.
    class Commissioning
      def initialize(report)
        @report = report
      end

      def render
        lines = [
          "Commissioning — #{@report.provider}",
          "Readiness: #{@report.readiness.to_s.upcase}",
          "Capabilities: #{present(@report.capabilities)}"
        ]
        lines << objective_line if @report.objective
        lines << telemetry_line unless @report.readiness == :unavailable
        lines << "Reason: #{@report.reason}" if @report.reason
        lines << if @report.ready?
          "A connected profile is proven ready. NO REPOSITORY WRITES WERE REQUIRED."
        else
          "No repository writes were made."
        end
        lines.join("\n")
      end

      private

      def objective_line
        transition = [@report.pre_state, @report.post_state].compact.map { |s| s.to_s.tr("_", " ") }.join(" → ")
        "Objective: #{@report.objective}#{" (#{transition})" unless transition.empty?}"
      end

      def telemetry_line
        "Cost: $#{format("%.2f", @report.cost_usd)}  Latency: #{@report.latency_s}s  " \
          "Tools: #{present(@report.tool_use)}  Network: #{present(@report.network)}"
      end

      def present(list)
        (list.nil? || list.empty?) ? "none" : list.join(", ")
      end
    end
  end
end
