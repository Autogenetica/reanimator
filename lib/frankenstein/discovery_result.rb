# frozen_string_literal: true

module Frankenstein
  # The outcome of running discovery over one repository: the collected facts
  # plus the profile they suggest. This is what the contract-review UI renders
  # ("here is what we found, and why") and what the resolver consumes.
  class DiscoveryResult
    # The suggested profile with the reasoning behind it.
    Suggestion = Struct.new(:profile, :confidence, :reason)

    attr_reader :repository, :facts

    def initialize(repository:, facts:)
      @repository = repository
      @facts = facts
    end

    # @return [DiscoveredFact, nil]
    def [](key)
      facts.find { |f| f.key == key.to_sym }
    end

    # @return [Boolean]
    def fact?(key)
      !self[key].nil?
    end

    # The machine value of a fact, or nil. Used to pull discovered command
    # strings into acceptance criteria.
    def value(key)
      self[key]&.value
    end

    # @param category [Symbol]
    # @return [Array<DiscoveredFact>]
    def in_category(category)
      facts.select { |f| f.category == category.to_sym }
    end

    # @return [Hash{Symbol=>Array<DiscoveredFact>}] facts grouped by category,
    #   in the canonical category order
    def by_category
      DiscoveredFact::CATEGORIES.each_with_object({}) do |category, grouped|
        found = in_category(category)
        grouped[category] = found unless found.empty?
      end
    end

    # Map of discovered command facts -> command strings, keyed by the profile
    # criterion they satisfy (:tests, :lint, :build, :dependencies, :assets).
    # @return [Hash{Symbol=>String}]
    def discovered_commands
      {
        tests: value(:test_command),
        lint: value(:lint_command),
        build: value(:build_command),
        dependencies: value(:dependencies_command),
        assets: value(:assets_command)
      }.compact
    end

    # @return [Suggestion]
    def suggestion
      @suggestion ||= ProfileInference.call(self)
    end

    # @return [Symbol] the suggested profile id
    def suggested_profile
      suggestion.profile
    end
  end
end
