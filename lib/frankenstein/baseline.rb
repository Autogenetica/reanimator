# frozen_string_literal: true

module Frankenstein
  # A timestamped, read-only measurement of a repository's current obligations
  # and pre-existing failures (specification sections 02 and 14). A baseline is
  # the organism measured before any operation: it separates verified claims,
  # failed claims, missing evidence, and skipped boundaries, and it carries the
  # policy version it was measured against so later runs can detect genuine
  # improvement or regression rather than noise.
  class Baseline
    attr_reader :contract, :results, :state, :generated_at, :executed

    def initialize(contract:, results:, state:, generated_at:, executed:)
      @contract = contract
      @results = results
      @state = state
      @generated_at = generated_at
      @executed = executed
    end

    # @return [Boolean] whether checks actually executed, versus were planned
    def executed? = @executed

    def repository = contract.repository

    def policy_version = contract.policy_version

    # Counts of each result status, e.g. {verified: 3, missing_evidence: 1}.
    # @return [Hash{Symbol=>Integer}]
    def tally
      results.each_with_object(Hash.new(0)) { |r, h| h[r.status] += 1 }
    end

    def results_with_status(status)
      results.select { |r| r.status == status.to_sym }
    end

    # Required criteria that failed - the actionable, blocking ones.
    def failing_required
      results.select { |r| r.required? && r.failed? }
    end

    # Required criteria that are neither verified nor accepted risk - the ones
    # that genuinely still need attention (failed, missing, planned, skipped).
    def unresolved_required
      results.select { |r| r.required? && !r.verified? && !r.accepted_risk? }
    end

    # Required criteria whose failure has been explicitly waived - accepted
    # risk, kept separate from verified vitality (section 15).
    def accepted_risks
      results.select(&:accepted_risk?)
    end

    # The first required criterion that failed, or nil - the natural repair
    # target. Callers ask the baseline rather than digging through #results.
    def first_failing_required_criterion
      failing_required.first&.criterion
    end

    # The result for a criterion id, or nil.
    def result_for(criterion_id)
      results.find { |r| r.criterion.id == criterion_id }
    end

    # Ids of required criteria that are verified - the set a later run must not
    # regress from.
    def verified_required_ids
      results.select { |r| r.required? && r.verified? }.map { |r| r.criterion.id }
    end

    # The required criteria the Verified Vitality Rate is measured over.
    # Accepted risk is deliberately excluded so it is reported separately
    # rather than counted as a failure (section 15).
    def rated_required
      results.select { |r| r.required? && !r.accepted_risk? }
    end

    # Verified Vitality Rate for active (required) obligations - the headline
    # dashboard metric from section 15, kept separate from accepted risk.
    # @return [Float] 0.0..1.0
    def verified_vitality_rate
      rated = rated_required
      return 1.0 if rated.empty?

      rated.count(&:verified?).to_f / rated.size
    end

    # A repository is proven when it is Alive with no failed or unproven
    # required criteria.
    def proven? = state.alive?

    def to_h
      {
        repository: repository.full_name,
        state: state.to_sym,
        executed: executed?,
        generated_at: generated_at.iso8601,
        policy_version: policy_version,
        verified_vitality_rate: verified_vitality_rate.round(3),
        tally: tally,
        results: results.map(&:to_h)
      }
    end
  end
end
