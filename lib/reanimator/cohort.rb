# frozen_string_literal: true

module Reanimator
  # A suggested triage grouping for a repository during intake (specification
  # section 04). Cohorts exist so a maintainer can accept sensible defaults in
  # bulk while still seeing - and overriding - the intent behind each grouping.
  # Crucially, the tool never preselects every repository; it recommends a
  # small, high-confidence set that can reach a useful baseline quickly.
  class Cohort
    attr_reader :key, :title, :default_intent, :treatment

    def initialize(key:, title:, default_intent:, treatment:)
      @key = key
      @title = title
      @default_intent = default_intent
      @treatment = treatment
      freeze
    end

    # Whether repositories in this cohort are recommended for active
    # onboarding (versus deferred, observed, or preserved).
    def recommended_for_onboarding?
      key == :active_original
    end

    ALL = {
      active_original: new(
        key: :active_original, title: "Active original repositories",
        default_intent: :maintain, treatment: "Recommend for onboarding."
      ),
      recent_experiment: new(
        key: :recent_experiment, title: "Recent experiments",
        default_intent: :incubate, treatment: "Suggest incubate or monitor."
      ),
      readme_only: new(
        key: :readme_only, title: "README-only concepts and presentations",
        default_intent: :incubate, treatment: "Ask whether to incubate, preserve, or ignore."
      ),
      archived: new(
        key: :archived, title: "Archived repositories",
        default_intent: :preserve, treatment: "Suggest preserve or retire; never auto-modernize."
      ),
      old_unarchived: new(
        key: :old_unarchived, title: "Old unarchived repositories",
        default_intent: :monitor, treatment: "Flag intent ambiguity rather than assuming maintenance."
      ),
      fork_observation: new(
        key: :fork_observation, title: "Forks",
        default_intent: :upstream, treatment: "Upstream observation until unique-commit intent is confirmed."
      ),
      constrained: new(
        key: :constrained, title: "Hardware or credential-dependent projects",
        default_intent: :monitor, treatment: "Suggest a constrained-environment profile."
      )
    }.freeze

    def self.fetch(key)
      ALL.fetch(key.to_sym) { raise UnknownError, "Unknown cohort #{key.inspect}." }
    end
  end
end
