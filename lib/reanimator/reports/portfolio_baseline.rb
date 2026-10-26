# frozen_string_literal: true

module Reanimator
  module Reports
    # The tangible artifact onboarding must produce (Appendix A): a portfolio
    # baseline that groups repositories by proof-of-life state and, for the ones
    # with gaps, names exactly what remains unproven. It ends by stating that no
    # source changed and no agent was required - the whole point of the first
    # run.
    class PortfolioBaseline
      # State display order: proven first, then attention, then dormant.
      STATE_ORDER = %i[alive at_risk needs_you unproven recovering diverged sleeping retired].freeze

      def initialize(baselines, name: "portfolio", generated_at: nil)
        @baselines = baselines
        @name = name
        @generated_at = generated_at || @baselines.map(&:generated_at).max || Time.now
      end

      def render
        ([banner] + state_groups + [footer]).join("\n\n")
      end

      private

      def banner
        [
          "REANIMATOR BASELINE",
          "Portfolio: #{@name}",
          "Generated: #{@generated_at.strftime("%Y-%m-%d %H:%M %Z")}",
          "Mode: read-only",
          "",
          "SELECTED FOR CONTINUOUS CARE",
          Reports.count(@baselines.size, "repository", "repositories")
        ].join("\n")
      end

      def state_groups
        grouped = @baselines.group_by { |b| b.state.to_sym }
        STATE_ORDER.filter_map do |state|
          entries = grouped[state]
          next unless entries

          ([state.to_s.upcase.tr("_", " ")] + entries.flat_map { |b| repository_lines(b) }).join("\n")
        end
      end

      def repository_lines(baseline)
        lines = ["  #{baseline.repository.name}"]
        gaps(baseline).each { |gap| lines << "    - #{gap}" }
        lines
      end

      # For a repository that is not fully Alive, the required criteria that are
      # not yet verified, with their reason.
      def gaps(baseline)
        return [] if baseline.state.alive?

        baseline.unresolved_required
          .map { |r| r.detail || "#{r.criterion.id} #{Reports.status_label(r.status)}" }
      end

      def footer
        ["NO SOURCE CHANGES WERE MADE", "No coding agent was required."].join("\n")
      end
    end
  end
end
