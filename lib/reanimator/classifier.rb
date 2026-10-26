# frozen_string_literal: true

module Reanimator
  # Assigns a repository to a triage cohort and a provisional lifecycle intent
  # from read-only evidence (specification sections 04 and 05). The classifier
  # is deliberately conservative: it flags ambiguity rather than assuming
  # maintenance, and it never treats its own suggestion as final - intent must
  # be confirmed before activation.
  class Classifier
    # Gems that imply a hardware- or credential-constrained environment.
    HARDWARE_MARKERS = %w[rpi_gpio pi_piper serialport dino artoo denko wiringpi].freeze
    RECENT_DAYS = 120
    STALE_DAYS = 365
    EXPERIMENT_COMMITS = 15

    # The result of classification: the cohort, the intent it suggests, how
    # confident that suggestion is, and why.
    Classification = Struct.new(:cohort, :suggested_intent, :confidence, :reason) do
      def recommended_for_onboarding? = cohort.recommended_for_onboarding?
    end

    attr_reader :repository, :discovery

    def initialize(repository, discovery: nil)
      @repository = repository
      @discovery = discovery
    end

    # @return [Classification]
    def classify
      cohort_key, confidence, reason = decide
      cohort = Cohort.fetch(cohort_key)
      Classification.new(
        cohort: cohort,
        suggested_intent: cohort.default_intent,
        confidence: Confidence[confidence],
        reason: reason
      )
    end

    private

    def decide
      metadata = repository.metadata

      if repository.fork? || discovery&.fact?(:fork_of)
        [:fork_observation, :high, "The repository is a fork; defaulting to upstream observation."]
      elsif hardware?
        [:constrained, :medium, "Hardware/credential-dependent gems detected; a constrained profile is safer."]
      elsif metadata.archived?
        [:archived, :high, "The repository is archived."]
      elsif readme_only?
        [:readme_only, :medium, "No recognized source language; looks like a concept or presentation."]
      elsif stale?
        [:old_unarchived, :medium, "No activity for over a year; intent is ambiguous rather than clearly maintained."]
      elsif experiment?
        [:recent_experiment, :medium, "Recent, low-commit repository; likely still an experiment."]
      else
        [:active_original, :high, "Active original repository with recognizable structure."]
      end
    end

    def hardware?
      body = repository.read("Gemfile").to_s + repository.read("Gemfile.lock").to_s
      HARDWARE_MARKERS.any? { |marker| body.include?(marker) } ||
        HARDWARE_MARKERS.any? { |marker| repository.name.include?(marker) }
    end

    def readme_only?
      repository.metadata.primary_language.nil? &&
        !repository.any?("*.gemspec") &&
        !repository.exist?("package.json") &&
        repository.any?("README*")
    end

    def stale?
      days = repository.metadata.days_since_activity
      days && days > STALE_DAYS
    end

    def experiment?
      days = repository.metadata.days_since_activity
      count = repository.metadata.commit_count
      return false unless days && count

      days <= RECENT_DAYS && count < EXPERIMENT_COMMITS
    end
  end
end
