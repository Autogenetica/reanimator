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

    # Verified Vitality Rate for active (required) obligations - the headline
    # dashboard metric from section 15, kept separate from accepted risk.
    # @return [Float] 0.0..1.0
    def verified_vitality_rate
      required = results.select(&:required?)
      return 1.0 if required.empty?

      required.count(&:verified?).to_f / required.size
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
