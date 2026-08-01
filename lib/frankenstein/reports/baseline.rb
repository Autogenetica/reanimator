# frozen_string_literal: true

module Frankenstein
  module Reports
    # A full single-repository baseline report. It separates verified, failed,
    # and unproven criteria the way section 14 requires, states the mode
    # plainly (read-only/planned vs executed), and ends with the promise that
    # nothing was changed.
    class Baseline
      def initialize(baseline)
        @baseline = baseline
      end

      def render
        [
          header,
          criteria_section,
          notes_section,
          "NO SOURCE CHANGES WERE MADE"
        ].compact.join("\n\n")
      end

      private

      def header
        contract = @baseline.contract
        intent = "#{contract.intent} (#{contract.intent_confirmed? ? "confirmed" : "provisional"})"
        required = @baseline.results.select(&:required?)
        rate = (@baseline.verified_vitality_rate * 100).round
        [
          "Baseline — #{@baseline.repository.full_name}",
          "State:   #{@baseline.state.to_s.upcase.tr("_", " ")} — #{@baseline.state.meaning}",
          "Mode:    #{@baseline.executed? ? "executed (bounded, read-only)" : "read-only (planned)"}",
          "Intent:  #{intent}",
          "Profile: #{contract.profile.id} (#{contract.profile_source})",
          "Contract: #{@baseline.policy_version}",
          "Verified Vitality Rate: #{rate}% (#{required.count(&:verified?)}/#{required.size} required)"
        ].join("\n")
      end

      def criteria_section
        lines = @baseline.results.map do |result|
          mark = result.required? ? "*" : " "
          timing = result.duration ? " (#{result.duration}s)" : ""
          detail = result.detail ? " — #{result.detail}" : ""
          "  #{Reports.glyph(result.status)}#{mark} #{result.criterion.id}: #{result.criterion.claim}#{detail}#{timing}"
        end
        (["Criteria (* = required):"] + lines).join("\n")
      end

      def notes_section
        return if @baseline.contract.notes.empty?

        (["Notes:"] + @baseline.contract.notes.map { |n| "  - #{n}" }).join("\n")
      end
    end
  end
end
