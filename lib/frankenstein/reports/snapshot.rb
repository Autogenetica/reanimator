# frozen_string_literal: true

module Frankenstein
  module Reports
    # Renders a recorded contract snapshot for a person rather than a machine:
    # what this repository is currently required to prove, and how to put that
    # on record so later drift has something to be measured against.
    class Snapshot
      def initialize(snapshot, saved_to: nil)
        @snapshot = snapshot
        @saved_to = saved_to
      end

      def render
        ([header] + [policy, proves, evidence].compact + [footer]).join("\n")
      end

      private

      def header
        "Contract snapshot — #{@snapshot.repository}\nTaken:    #{taken_at}"
      end

      # A freshly recorded snapshot holds a Time; one loaded from disk holds
      # the string it was serialized as. They must read the same.
      def taken_at
        moment = @snapshot.taken_at
        moment.is_a?(Time) ? moment.iso8601 : moment
      end

      def policy
        "Intent:   #{@snapshot.intent}   Profile: #{@snapshot.profile}   " \
          "Security: #{@snapshot.security_posture} posture"
      end

      def proves
        required = @snapshot.criteria.count { |criterion| criterion[:required] }
        line = "Proves:   #{count(@snapshot.criteria, "criterion", "criteria")} (#{required} required)"
        return line if @snapshot.waivers.empty?

        "#{line}, #{count(@snapshot.waivers, "accepted risk", "accepted risks")}"
      end

      # The evidence half of the snapshot: the facts that drift can narrow
      # without anyone editing .frankenstein.yml.
      def evidence
        parts = []
        parts << "runtimes #{@snapshot.support_matrix.join(", ")}" if @snapshot.support_matrix.any?
        parts << "security gates #{@snapshot.security_controls.join(", ")}" if @snapshot.security_controls.any?
        "Evidence: #{parts.join(" · ")}" if parts.any?
      end

      def footer
        return "\nRecorded to #{@saved_to}. Compare later with: frankenstein drift --since #{@saved_to}" if @saved_to

        "\nNothing was written. Record this with --save FILE, then compare later with --since FILE."
      end

      def count(collection, singular, plural)
        "#{collection.size} #{(collection.size == 1) ? singular : plural}"
      end
    end
  end
end
