# frozen_string_literal: true

module Reanimator
  module Reports
    # Renders a recorded contract snapshot for a person rather than a machine:
    # what this repository is currently required to prove, and how to put that
    # on record so later drift has something to be measured against.
    class Snapshot
      def initialize(snapshot, saved_to: nil, record_with: "reanimator drift --record")
        @snapshot = snapshot
        @saved_to = saved_to
        @record_with = record_with
      end

      def render
        ([header] + [policy, proves, evidence].compact + [footer]).join("\n")
      end

      private

      def header
        "Contract snapshot — #{@snapshot.repository}\nTaken:    #{@snapshot.taken_at}"
      end

      def policy
        "Intent:   #{@snapshot.intent}   Profile: #{@snapshot.profile}   " \
          "Security: #{@snapshot.security_posture} posture"
      end

      def proves
        required = @snapshot.criteria.count { |criterion| criterion[:required] }
        line = "Proves:   #{Reports.count(@snapshot.criteria.size, "criterion", "criteria")} (#{required} required)"
        return line if @snapshot.waivers.empty?

        "#{line}, #{Reports.count(@snapshot.waivers.size, "accepted risk")}"
      end

      # The evidence half of the snapshot: the facts that drift can narrow
      # without anyone editing .reanimator.yml.
      def evidence
        parts = []
        parts << "runtimes #{@snapshot.support_matrix.join(", ")}" if @snapshot.support_matrix.any?
        parts << "security gates #{@snapshot.security_controls.join(", ")}" if @snapshot.security_controls.any?
        "Evidence: #{parts.join(" · ")}" if parts.any?
      end

      # Whichever way this snapshot was recorded, the next thing a maintainer
      # wants is the command that compares against it - so the footer names
      # that, not the flag they happened to use.
      def footer
        return "\nRecorded to #{@saved_to}. Compare later with: reanimator drift" if @saved_to

        "\nNothing was written. Record this with `#{@record_with}` so later drift " \
          "has something to be measured against."
      end
    end
  end
end
