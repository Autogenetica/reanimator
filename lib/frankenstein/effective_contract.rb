# frozen_string_literal: true

require "digest"

module Frankenstein
  # The fully resolved combination of policy layers plus accepted discoveries
  # (specification section 02): exactly what Frankenstein must prove for one
  # repository. It is what the contract-review UI shows, what the baseline
  # runs, and what every run is versioned against. It knows how to render
  # itself back into a minimal, round-trippable .frankenstein.yml.
  class EffectiveContract
    attr_reader :repository, :intent, :profile, :criteria, :discovery,
      :security_posture, :autonomy, :protected_paths, :notes,
      :profile_source, :intent_confirmed

    def initialize(repository:, intent:, profile:, criteria:, discovery:,
      security_posture:, autonomy:, protected_paths:, profile_source:,
      intent_confirmed:, notes: [])
      @repository = repository
      @intent = intent
      @profile = profile
      @criteria = criteria
      @discovery = discovery
      @security_posture = security_posture
      @autonomy = autonomy
      @protected_paths = protected_paths
      @profile_source = profile_source
      @intent_confirmed = intent_confirmed
      @notes = notes
    end

    def intent_confirmed? = @intent_confirmed

    # @return [Array<AcceptanceCriterion>] criteria whose failure blocks
    def required_criteria = criteria.select(&:required?)

    # @return [Array<AcceptanceCriterion>] non-blocking criteria
    def optional_criteria = criteria.reject(&:required?)

    # Criteria that touch verifier definitions or protected contract surfaces
    # and therefore always receive elevated review (section 09).
    def verifier_criteria = criteria.select(&:elevated?)

    # A short, stable fingerprint of the materialized contract, so each run can
    # be attributed to the exact policy it was measured against (section 17:
    # "version the effective contract used for each run").
    def policy_version
      @policy_version ||= "#{profile.id}@#{Digest::SHA256.hexdigest(canonical.to_s)[0, 12]}"
    end

    # The minimal, owner-facing declaration. This is the target for ordinary
    # configuration (section 05): one lifecycle decision and one profile.
    def to_minimal_hash
      {version: ContractFile::CURRENT_VERSION, intent: intent.to_sym, profile: profile.id}
    end

    # The fuller contract hash used for advanced export. Must round-trip
    # through {ContractFile} without semantic loss (section 07).
    def to_contract_hash
      to_minimal_hash.merge(
        acceptance: {
          checks: criteria.map { |c| c.to_h.slice(:id, :evaluator, :run, :target, :required).compact }
        },
        security: {posture: security_posture.to_sym},
        autonomy: autonomy,
        protected_paths: protected_paths
      )
    end

    def to_h
      {
        repository: repository.full_name,
        intent: intent.to_sym,
        intent_confirmed: intent_confirmed?,
        profile: profile.id,
        profile_source: profile_source,
        security_posture: security_posture.to_sym,
        autonomy: autonomy,
        protected_paths: protected_paths,
        policy_version: policy_version,
        criteria: criteria.map(&:to_h),
        notes: notes
      }
    end

    private

    # The subset that defines the contract's identity for fingerprinting.
    def canonical
      {
        intent: intent.to_sym,
        profile: profile.id,
        posture: security_posture.to_sym,
        autonomy: autonomy,
        protected: protected_paths.sort,
        criteria: criteria.map { |c| [c.id, c.evaluator, c.run, c.required] }.sort_by(&:first)
      }
    end
  end
end
