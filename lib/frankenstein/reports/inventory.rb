# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders a classified portfolio: repositories grouped by suggested cohort,
    # each with the strongest evidence behind the grouping (section 04). It
    # leads with the small recommended set, honoring the rule never to
    # preselect everything.
    class Inventory
      def initialize(portfolio)
        @portfolio = portfolio
      end

      def render
        [header, cohort_sections].join("\n\n")
      end

      private

      def header
        recommended = @portfolio.recommended.map(&:name)
        [
          "Portfolio inventory — #{Reports.count(@portfolio.size, "repository", "repositories")}",
          "Recommended for onboarding: #{recommended.empty? ? "(none yet)" : recommended.join(", ")}"
        ].join("\n")
      end

      def cohort_sections
        @portfolio.by_cohort.map do |key, entries|
          cohort = Cohort.fetch(key)
          lines = entries.map { |e| "  - #{e.name} — #{e.classification.reason}" }
          (["#{cohort.title} → suggest #{cohort.default_intent}:"] + lines).join("\n")
        end.join("\n\n")
      end
    end
  end
end
