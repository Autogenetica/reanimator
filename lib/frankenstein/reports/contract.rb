# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders an effective contract for review: the resolved value of every
    # decision, where it came from, and what is protected. Section 07 requires
    # the resolved value, its source, and any elevated-review surfaces to be
    # visible - this is the "minimal view" of the policy explorer.
    class Contract
      def initialize(contract)
        @contract = contract
      end

      def render
        [header, autonomy_section, criteria_section, protected_section, notes_section]
          .compact.join("\n\n")
      end

      private

      def header
        [
          "Effective contract — #{@contract.repository.full_name}",
          "Intent:   #{@contract.intent} (#{@contract.intent_confirmed? ? "confirmed" : "provisional"})",
          "Profile:  #{@contract.profile.id} (#{@contract.profile_source}) — #{@contract.profile.summary}",
          "Security: #{@contract.security_posture} posture",
          "Policy version: #{@contract.policy_version}"
        ].join("\n")
      end

      def autonomy_section
        pairs = @contract.autonomy.map { |k, v| "#{k}=#{v}" }.join("  ")
        "Autonomy: #{pairs}"
      end

      def criteria_section
        lines = @contract.criteria.map do |c|
          mark = c.required? ? "*" : " "
          elevated = c.elevated? ? " [elevated review]" : ""
          how = c.run || c.evaluator
          "  #{mark} #{c.id}: #{c.claim} — #{how}#{elevated}"
        end
        (["Criteria (* = required):"] + lines).join("\n")
      end

      def protected_section
        (["Protected paths (elevated review to change):"] +
          @contract.protected_paths.map { |p| "  - #{p}" }).join("\n")
      end

      def notes_section
        return if @contract.notes.empty?

        (["Notes:"] + @contract.notes.map { |n| "  - #{n}" }).join("\n")
      end
    end
  end
end
