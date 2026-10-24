# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders a portfolio's compatibility graph (specification section 10):
    # which repositories must stay alive together, what role each plays, and
    # which edge each gate is there to prove.
    class Families
      def initialize(families)
        @families = families
      end

      def render
        return "No repository families detected." if @families.empty?

        ([header] + @families.map { |family| section(family) }).join("\n\n")
      end

      private

      def header
        count = @families.size
        "Repository families — #{Reports.count(count, "family", "families")} " \
          "(#{@families.sum(&:size)} repositories that must stay alive together)"
      end

      def section(family)
        lines = ["#{family.id}:"]
        family.members.each do |member|
          lines << "  - #{member.full_name} (#{member.role.to_s.tr("_", " ")})"
        end
        family.relationships.each do |relationship|
          lines << "  edge: #{relationship.label}"
          lines << "        #{relationship.description}"
        end
        family.gates.each { |gate| lines << "  gate: #{gate.label}" }
        lines.join("\n")
      end
    end
  end
end
