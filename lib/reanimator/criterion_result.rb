# frozen_string_literal: true

module Reanimator
  # The outcome of evaluating one acceptance criterion during a baseline. Its
  # status is drawn from the vocabulary section 14 requires a baseline to
  # separate: verified claims, failed claims, missing evidence, skipped
  # boundaries, and accepted risks - plus "planned" for the read-only,
  # non-executing default, and "unavailable" for proof Reanimator itself
  # cannot establish yet (a boot smoke needs a service it does not run).
  class CriterionResult
    STATUSES = %i[verified failed missing_evidence skipped accepted_risk planned unavailable error].freeze

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

    # A required criterion whose failure has been explicitly accepted via a
    # waiver: not verified, but not blocking either.
    def accepted_risk? = status == :accepted_risk

    # Whether this result contributes proof (a verified required criterion).
    def proven? = verified?

    # Whether the criterion is still unproven: no evidence either way yet.
    # An evaluator that errored belongs here too - "we could not tell" is not
    # proof, and leaving it out would let a broken check read as green.
    def unproven? = %i[missing_evidence planned skipped unavailable error].include?(status)

    # Whether a person can act on this result. A failed, unproven or errored
    # check is something to fix - including a skipped one, such as a misspelt
    # evaluator or a required matrix nobody declared. Planned (not asked to
    # run) and unavailable (beyond Reanimator for now) are not.
    def actionable? = %i[failed missing_evidence skipped error].include?(status)

    def required? = criterion.required?

    # Whether this result is eligible to be waived: a required obligation that
    # is not proven and has not already been accepted.
    def waivable? = required? && !verified? && !accepted_risk?

    # A copy of this result recorded as accepted risk under the given waiver.
    # The criterion is still not verified - its failure is explicitly accepted.
    #
    # @param waiver [Waiver]
    # @return [CriterionResult]
    def accepted_via(waiver)
      CriterionResult.new(
        criterion: criterion, status: :accepted_risk,
        detail: waiver.acceptance_of(self), evidence: evidence, duration: duration
      )
    end

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
