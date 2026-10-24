# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders configuration drift (specification section 06) so the two kinds of
    # change never blur together: policy changes come first, under a heading
    # that says a human is needed, and benign changes follow as information.
    class Drift
      def initialize(report, record_with: "frankenstein drift --record")
        @report = report
        @record_with = record_with
      end

      def render
        return quiet unless @report.drifted?

        ([header] + sections + [verdict, next_step]).compact.join("\n\n")
      end

      private

      def quiet
        "#{header}\nNo drift — the contract still matches the recorded snapshot."
      end

      def header
        "Configuration drift — #{@report.repository}\nSince: #{@report.since}"
      end

      def sections
        [
          section("Policy changes (review required)", @report.policy_changes, "!"),
          section("Benign changes", @report.benign_changes, "·")
        ].compact
      end

      def section(title, changes, marker)
        return if changes.empty?

        lines = ["#{title} — #{changes.size}"]
        changes.each do |change|
          lines << "  #{marker} #{change.summary}"
          lines << "    #{change.explanation}"
        end
        lines.join("\n")
      end

      # A maintainer whose build just went red needs to know how to accept
      # drift they meant to introduce; the report is the only place they are
      # looking.
      def next_step
        "Intended? Re-record with: #{@record_with}"
      end

      def verdict
        return "No policy changes; nothing here needs a decision." unless @report.requires_review?

        count = @report.policy_changes.size
        "REVIEW REQUIRED: #{count} policy change#{"s" unless count == 1} — less is being proven than before."
      end
    end
  end
end
