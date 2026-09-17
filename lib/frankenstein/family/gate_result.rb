# frozen_string_literal: true

module Frankenstein
  class Family
    # The outcome of one cross-repository gate. Section 10 is explicit that
    # "family failures identify the exact edge that broke, not merely the
    # repository that ran CI", so a result carries the relationship it was
    # proving, not just a repository name.
    class GateResult
      STATUSES = %i[verified failed missing_evidence planned skipped].freeze

      attr_reader :gate, :relationship, :status, :detail, :duration

      def initialize(gate:, status:, relationship: nil, detail: nil, duration: nil)
        @gate = gate
        @status = status.to_sym
        unless STATUSES.include?(@status)
          raise UnknownError, "Unknown gate result status #{status.inspect}."
        end

        @relationship = relationship
        @detail = detail
        @duration = duration
      end

      def verified? = status == :verified

      def failed? = status == :failed

      # Not proven yet: nothing ran, or no downstream proof exists.
      def unresolved? = %i[missing_evidence planned skipped].include?(status)

      # The exact edge this result speaks for.
      def edge
        relationship&.label || "#{gate.on} -> #{gate.requires_repository}"
      end

      def to_h
        {
          edge: edge, on: gate.on, requires: gate.requires_repository,
          status: status, detail: detail, duration: duration
        }.compact
      end
    end
  end
end
