# frozen_string_literal: true

module Frankenstein
  # A reusable bundle of inferred or declared obligations for a common project
  # shape - ruby-gem, rails-app, ruby-cli (specification section 02). A
  # profile says what "healthy" *usually* looks like; it removes repetitive
  # configuration without hiding the resulting contract. Profiles compose:
  # rails-app inherits from web-application, and both resolve against the
  # detected evidence of a specific repository.
  class VitalityProfile
    # @return [Symbol] stable profile id, e.g. :"ruby-gem"
    attr_reader :id
    # @return [String] one-line description
    attr_reader :summary
    # @return [Array<Symbol>] profiles this one inherits obligations from
    attr_reader :inherits
    # @return [Array<AcceptanceCriterion>] criteria contributed by this profile
    attr_reader :criteria

    def initialize(id:, summary:, inherits: [], criteria: [])
      @id = id.to_sym
      @summary = summary
      @inherits = Array(inherits).map(&:to_sym)
      @criteria = criteria
      freeze
    end

    # The fully-resolved criteria for this profile, including inherited ones,
    # de-duplicated by id with the most specific (this profile) winning.
    #
    # @param registry [#fetch] profile lookup, defaults to {Profiles}
    # @return [Array<AcceptanceCriterion>]
    def resolved_criteria(registry: Profiles)
      inherited = inherits.flat_map { |parent| registry.fetch(parent).resolved_criteria(registry: registry) }
      by_id = {}
      (inherited + criteria).each { |c| by_id[c.id] = c }
      by_id.values
    end

    def to_h
      {id: id, summary: summary, inherits: inherits}
    end
  end
end
