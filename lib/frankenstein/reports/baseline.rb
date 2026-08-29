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
          accepted_risk_section,
          notes_section,
          "NO SOURCE CHANGES WERE MADE"
        ].compact.join("\n\n")
      end

      private

      def accepted_risk_section
        risks = @baseline.accepted_risks
        return if risks.empty?

        lines = risks.map { |r| "  #{Reports.glyph(:accepted_risk)} #{r.criterion.id}: #{r.detail}" }
        (["Accepted risk (waived) — counted as risk, not verified vitality:"] + lines).join("\n")
      end

      def header
        contract = @baseline.contract
        intent = "#{contract.intent} (#{contract.intent_confirmed? ? "confirmed" : "provisional"})"
        # Accepted risk is excluded from the rate's denominator (kept separate),
        # so the fraction and the percentage agree.
        rated = @baseline.results.select { |r| r.required? && !r.accepted_risk? }
        accepted = @baseline.accepted_risks.size
        rate = (@baseline.verified_vitality_rate * 100).round
        vvr = "Verified Vitality Rate: #{rate}% (#{rated.count(&:verified?)}/#{rated.size} required"
        vvr += ", #{accepted} accepted risk" if accepted.positive?
        vvr += ")"
        [
          "Baseline — #{@baseline.repository.full_name}",
          "State:   #{@baseline.state.to_s.upcase.tr("_", " ")} — #{@baseline.state.meaning}",
          "Mode:    #{@baseline.executed? ? "executed (bounded, read-only)" : "read-only (planned)"}",
          "Intent:  #{intent}",
          "Profile: #{contract.profile.id} (#{contract.profile_source})",
          "Contract: #{@baseline.policy_version}",
          vvr
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
