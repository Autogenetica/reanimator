# frozen_string_literal: true

module Frankenstein
  # The outcome of evaluating one acceptance criterion during a baseline. Its
  # status is drawn from the vocabulary section 14 requires a baseline to
  # separate: verified claims, failed claims, missing evidence, skipped
  # boundaries, and accepted risks - plus "planned" for the read-only,
  # non-executing default.
  class CriterionResult
    STATUSES = %i[verified failed missing_evidence skipped accepted_risk planned error].freeze

    attr_reader :criterion, :status, :detail, :evidence, :duration

    def initialize(criterion:, status:, detail: nil, evidence: nil, duration: nil)
      @criterion = criterion
      @status = status.to_sym
      unless STATUSES.include?(@status)
        raise UnknownError, "Unknown criterion result status #{status.inspect}."
      end
      @detail = detail
      @evidence = evidence
      @duration = duration
    end

    def verified? = status == :verified

    def failed? = status == :failed

    # Whether this result contributes proof (a verified required criterion).
    def proven? = verified?

    # Whether the criterion is still unproven: no executable evidence yet.
    def unproven? = %i[missing_evidence planned skipped].include?(status)

    def required? = criterion.required?

    def to_h
      {
        id: criterion.id,
        claim: criterion.claim,
        required: criterion.required?,
        status: status,
        detail: detail,
        duration: duration
      }.compact
    end
  end
end
