# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders discovered facts grouped by detector category, each with its
    # confidence and provenance. This is the contract-review surface's core
    # promise from section 06: the report can always answer "Why does
    # Frankenstein believe this?"
    class Discovery
      def initialize(discovery)
        @discovery = discovery
      end

      def render
        sections = [suggested_profile]
        @discovery.by_category.each do |category, facts|
          sections << category_section(category, facts)
        end
        sections << "No facts discovered." if @discovery.facts.empty?
        sections.join("\n\n")
      end

      private

      def suggested_profile
        s = @discovery.suggestion
        "Suggested profile: #{s.profile} (#{s.confidence}) — #{s.reason}"
      end

      def category_section(category, facts)
        lines = facts.map do |fact|
          "  [#{fact.confidence}] #{fact.claim}  ← #{fact.provenance.explanation}"
        end
        (["#{category.to_s.tr("_", " ")}:"] + lines).join("\n")
      end
    end
  end
end
