# frozen_string_literal: true

module Reanimator
  module Reports
    # Drift across a portfolio, rendered as a triage list rather than a pile of
    # diffs. The ordering is the point: repositories that need a human come
    # first and carry the reason for each policy change, repositories that
    # merely changed follow as information, and repositories with nothing
    # recorded are named rather than quietly counted as fine.
    class PortfolioDrift
      def initialize(drift)
        @drift = drift
      end

      def render
        ([banner] + sections + [verdict, footer]).compact.join("\n\n")
      end

      private

      def banner
        [
          "REANIMATOR DRIFT",
          "Portfolio: #{@drift.name}",
          "Generated: #{@drift.generated_at.strftime("%Y-%m-%d %H:%M %Z")}",
          "Mode: read-only"
        ].join("\n")
      end

      def sections
        [
          review_section,
          listing("CHANGED, BENIGN", @drift.benign) { |entry| change_lines(entry.report.benign_changes, "·", 4) },
          listing("UNCHANGED", @drift.unchanged),
          listing("NOT RECORDED", @drift.unrecorded) { ["    nothing to compare against yet"] },
          listing("COULD NOT READ", @drift.failed) { |entry| ["    #{entry.error}"] }
        ].compact
      end

      # The only section that spells out *why* each change matters: these are
      # the ones somebody has to decide about.
      def review_section
        listing("REVIEW REQUIRED", @drift.policy_changed) do |entry|
          changes = entry.report.policy_changes
          ["    #{Reports.count(changes.size, "policy change")}"] + change_lines(changes, "!", 6, explain: true)
        end
      end

      def listing(title, entries)
        return if entries.empty?

        lines = ["#{title} — #{Reports.count(entries.size, "repository", "repositories")}"]
        entries.each do |entry|
          lines << "  #{entry.name}"
          lines.concat(block_given? ? yield(entry) : [])
        end
        lines.join("\n")
      end

      def change_lines(changes, marker, indent, explain: false)
        pad = " " * indent
        changes.flat_map do |change|
          lines = ["#{pad}#{marker} #{change.summary}"]
          lines << "#{pad}  #{change.explanation}" if explain
          lines
        end
      end

      # Two separate reasons a portfolio can need a human, reported separately
      # because they call for different things: drift somebody has to approve,
      # and a snapshot nobody can read.
      def verdict
        return "No policy changes across the portfolio; nothing here needs a decision." unless @drift.requires_review?

        [policy_verdict, failure_verdict].compact.join("\n\n")
      end

      def policy_verdict
        repositories = @drift.policy_changed
        return if repositories.empty?

        total = repositories.sum { |entry| entry.report.policy_changes.size }
        "REVIEW REQUIRED: #{Reports.count(total, "policy change")} across " \
          "#{Reports.count(repositories.size, "repository", "repositories")} — less is being proven than before.\n" \
          "Intended? Re-record with: #{@drift.store.record_command}"
      end

      def failure_verdict
        failures = @drift.failed
        return if failures.empty?

        "REVIEW REQUIRED: #{Reports.count(failures.size, "repository", "repositories")} could not be read, " \
          "so drift could not be ruled out there."
      end

      # The read-only promise, stated precisely. Recording writes snapshot
      # files and nothing else, so the report says which it did rather than
      # claiming nothing happened.
      def footer
        recorded = @drift.entries.count { |entry| entry.recorded_to }
        return "NO FILES WERE WRITTEN. NO SOURCE CHANGES WERE MADE." if recorded.zero?

        "Recorded #{Reports.count(recorded, "snapshot")}. NO SOURCE CHANGES WERE MADE."
      end
    end
  end
end
