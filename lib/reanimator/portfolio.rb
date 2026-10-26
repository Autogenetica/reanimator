# frozen_string_literal: true

module Reanimator
  # The set of repositories visible to one installation, grouped for triage and
  # stewardship (specification section 02). Building a portfolio is the very
  # first onboarding step (section 03 stage 1): classify before acting. It is
  # read-only and never preselects everything - the recommended set is the
  # small, high-confidence group of active originals (section 04 default).
  class Portfolio
    # One repository plus how intake classified it.
    Entry = Struct.new(:repository, :classification) do
      def name = repository.name

      def cohort = classification.cohort

      def suggested_intent = classification.suggested_intent

      def recommended? = classification.recommended_for_onboarding?
    end

    attr_reader :entries

    def initialize(entries)
      @entries = entries
    end

    # Classifies each path that is a repository, skipping the rest.
    # @param paths [Array<String>]
    # @return [Portfolio]
    def self.scan(paths)
      entries = paths.filter_map do |path|
        repository = begin
          Repository.at(path)
        rescue RepositoryError
          Reanimator.logger.warn("Skipping #{path.inspect}: not a repository.")
          nil
        end
        next unless repository

        Entry.new(repository: repository, classification: Classifier.new(repository).classify)
      end

      new(entries)
    end

    def size = entries.size

    # @return [Array<Entry>] repositories recommended for active onboarding
    def recommended = entries.select(&:recommended?)

    # Entries grouped by cohort, in the canonical cohort order.
    # @return [Hash{Symbol=>Array<Entry>}]
    def by_cohort
      Cohort::ALL.keys.each_with_object({}) do |key, grouped|
        found = entries.select { |e| e.cohort.key == key }
        grouped[key] = found unless found.empty?
      end
    end

    def to_h
      {
        size: size,
        recommended: recommended.map(&:name),
        cohorts: by_cohort.transform_values { |es| es.map(&:name) }
      }
    end
  end
end
