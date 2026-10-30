# frozen_string_literal: true

module Reanimator
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
        lines << "REANIMATOR / VITALITY"
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

      # Agrees with the exit status: "attention needed" only when a required
      # check needs a human, not when checks were merely planned.
      def checks_summary
        planned = @baseline.unresolved_required.count { |r| r.status == :planned }
        unavailable = @baseline.unresolved_required.count { |r| r.status == :unavailable }
        if @baseline.needs_attention?
          "Attention needed: #{@baseline.escalations.size} required check(s) need a human."
        elsif planned.positive?
          "Not proven yet: #{planned} required check(s) were planned, not run; run with --execute to prove them."
        elsif unavailable.positive?
          "Not proven yet: #{unavailable} required check(s) need proof Reanimator cannot establish yet."
        elsif @baseline.executed?
          "No maintenance change was required."
        else
          "No source changes were made. Evidence is read-only; run with execution to confirm."
        end
      end
    end
  end
end
