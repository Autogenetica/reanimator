# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders a repository's vitality as the GitHub Check surface from section
    # 15 - the compact, scannable artifact a maintainer sees on a commit. A
    # healthy baseline that changed nothing says so explicitly: healthy silence
    # made visible.
    class GitHubCheck
      def initialize(baseline)
        @baseline = baseline
      end

      def render
        lines = []
        lines << "FRANKENSTEIN / VITALITY"
        lines << @baseline.state.to_s.upcase.tr("_", " ")
        lines << "Verified: #{@baseline.generated_at.strftime("%Y-%m-%d %H:%M %Z")}"
        lines << "Contract: #{@baseline.policy_version}"
        lines << "Agent: none required"
        @baseline.results.each do |result|
          lines << "#{Reports.glyph(result.status)} #{result.criterion.claim}"
        end
        lines << checks_summary
        lines.compact.join("\n")
      end

      private

      def checks_summary
        if unproven_or_failed.positive?
          "Attention needed: #{unproven_or_failed} required check(s) are not yet proven."
        elsif @baseline.executed?
          "No maintenance change was required."
        else
          "No source changes were made. Evidence is read-only; run with execution to confirm."
        end
      end

      def unproven_or_failed
        @baseline.unproven_required.size
      end
    end
  end
end
