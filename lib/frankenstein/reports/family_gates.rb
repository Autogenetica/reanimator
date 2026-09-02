# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders cross-repository gate results. The point of section 10 is that a
    # family failure names the *edge* that broke, so every line leads with the
    # relationship rather than with whichever repository happened to run.
    class FamilyGates
      def initialize(family, results)
        @family = family
        @results = results
      end

      def render
        ([header] + lines + [footer]).compact.join("\n")
      end

      private

      def header = "Family gates — #{@family.id}"

      def lines
        return ["  (no gates declared or inferred)"] if @results.empty?

        @results.map do |result|
          detail = result.detail ? " — #{result.detail}" : ""
          timing = result.duration ? " (#{result.duration}s)" : ""
          "  #{Reports.glyph(result.status)} #{result.edge}#{detail}#{timing}"
        end
      end

      def footer
        broken = @results.select(&:failed?)
        return "All family edges hold." if broken.empty? && @results.any?(&:verified?)
        return nil if broken.empty?

        "BROKEN EDGE#{"S" unless broken.size == 1}: #{broken.map(&:edge).join("; ")}"
      end
    end
  end
end
