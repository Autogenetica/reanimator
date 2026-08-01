# frozen_string_literal: true

module Frankenstein
  # A claim inferred from evidence - "RSpec exists", "Docker image builds in
  # CI", "supported Ruby is 3.1-3.3" - carrying its source, confidence, and
  # human-review status (specification sections 02 and 06). A discovered fact
  # is a *proposal*, not a decision: it becomes declared policy only once a
  # human accepts it.
  class DiscoveredFact
    # Detector categories from section 06. A fact always belongs to exactly one.
    CATEGORIES = %i[
      ecosystem commands support_matrix security_controls
      deployment contracts relationships operational_proof
    ].freeze

    # Review lifecycle of a fact.
    STATUSES = %i[proposed accepted rejected edited].freeze

    # @return [Symbol] a stable identifier within its repository, e.g. :rspec
    attr_reader :key
    # @return [Symbol] one of {CATEGORIES}
    attr_reader :category
    # @return [String] human-readable claim
    attr_reader :claim
    # @return [Object] the machine-usable value behind the claim
    attr_reader :value
    # @return [Confidence]
    attr_reader :confidence
    # @return [Provenance]
    attr_reader :provenance
    # @return [Symbol] one of {STATUSES}
    attr_reader :status

    def initialize(key:, category:, claim:, provenance:, value: true, confidence: Confidence::MEDIUM, status: :proposed)
      raise UnknownError, "Unknown detector category #{category.inspect}." unless CATEGORIES.include?(category.to_sym)
      raise UnknownError, "Unknown fact status #{status.inspect}." unless STATUSES.include?(status.to_sym)

      @key = key.to_sym
      @category = category.to_sym
      @claim = claim
      @value = value
      @confidence = Confidence[confidence]
      @provenance = provenance
      @status = status.to_sym
    end

    # Returns a copy accepted by a human. Acceptance is what turns an inference
    # into declared policy (section 06 conflict resolution rule 4).
    # @return [DiscoveredFact]
    def accept
      with(status: :accepted)
    end

    # Returns a copy the human explicitly rejected.
    # @return [DiscoveredFact]
    def reject
      with(status: :rejected)
    end

    # Returns a copy with an edited value, recorded as human-edited.
    # @return [DiscoveredFact]
    def edit(new_value)
      with(value: new_value, status: :edited)
    end

    def accepted? = status == :accepted

    def rejected? = status == :rejected

    # A fact "counts" toward the contract when a human has not rejected it.
    def active? = status != :rejected

    def to_h
      {
        key: key,
        category: category,
        claim: claim,
        value: value,
        confidence: confidence.to_sym,
        status: status,
        provenance: provenance.to_h
      }
    end

    private

    def with(**changes)
      DiscoveredFact.new(
        key: changes.fetch(:key, key),
        category: changes.fetch(:category, category),
        claim: changes.fetch(:claim, claim),
        value: changes.fetch(:value, value),
        confidence: changes.fetch(:confidence, confidence),
        provenance: changes.fetch(:provenance, provenance),
        status: changes.fetch(:status, status)
      )
    end
  end
end
