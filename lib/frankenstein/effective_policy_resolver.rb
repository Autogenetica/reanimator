# frozen_string_literal: true

module Frankenstein
  # Materializes an {EffectiveContract} from the precedence stack in section
  # 07. For this read-only slice the layers that participate are the product
  # safety floor (non-bypassable), the repository contract (owner declarations
  # in .frankenstein.yml), and runtime discovery (detected commands and
  # metadata, which may never authorize weaker behavior by itself). Higher
  # organization/portfolio/family layers plug in at the same seam later.
  #
  # Two rules are enforced here, not merely documented:
  #   * an owner declaration wins over inference, but
  #   * neither an owner declaration nor discovery may loosen the safety floor.
  class EffectivePolicyResolver
    # v1 autonomy defaults (section 20): observe and diagnose on; repair and
    # submit opt-in; merge off.
    DEFAULT_AUTONOMY = {
      observe: :automatic,
      diagnose: :automatic,
      repair: :disabled,
      submit: :disabled,
      merge: :disabled
    }.freeze

    attr_reader :repository, :discovery

    def initialize(repository, discovery: nil)
      @repository = repository
      @discovery = discovery || Discovery.new(repository).run
    end

    # @return [EffectiveContract]
    def resolve
      intent, intent_confirmed = resolve_intent
      profile, profile_source = resolve_profile(intent)
      autonomy, autonomy_notes = SafetyFloor.clamp_autonomy(resolve_autonomy)

      EffectiveContract.new(
        repository: repository,
        intent: intent,
        intent_confirmed: intent_confirmed,
        profile: profile,
        profile_source: profile_source,
        criteria: build_criteria(profile),
        discovery: discovery,
        security_posture: resolve_security_posture,
        autonomy: autonomy,
        protected_paths: SafetyFloor.protected_paths(declared_protected_paths),
        notes: autonomy_notes
      )
    end

    private

    def declared = repository.declared

    # Assigned intent wins, then a declared one, then a provisional suggestion
    # from the classifier. Only the first two count as "confirmed".
    def resolve_intent
      if repository.intent
        [LifecycleIntent.fetch(repository.intent), true]
      elsif declared&.intent
        [LifecycleIntent.fetch(declared.intent), true]
      else
        suggestion = Classifier.new(repository, discovery: discovery).classify
        [LifecycleIntent.fetch(suggestion.suggested_intent), false]
      end
    end

    # A declared profile always wins over inference (section 06). When the
    # inferred profile is rails-app but the intent is to preserve, the
    # historical variant is the better fit.
    def resolve_profile(intent)
      if declared&.profile
        [Profiles.fetch(declared.profile), :declared]
      else
        id = discovery.suggested_profile
        id = :"rails-legacy" if id == :"rails-app" && intent.to_sym == :preserve
        [Profiles.fetch(id), :inferred]
      end
    end

    # Profile criteria, with discovered commands substituted in for the
    # matching defaults (section 00: reuse detected checks; surface missing
    # proof), plus any checks the owner declared.
    def build_criteria(profile)
      commands = discovery.discovered_commands
      base = profile.resolved_criteria.map do |criterion|
        run = commands[criterion.id]
        run ? with_run(criterion, run) : criterion
      end
      base + declared_criteria
    end

    def with_run(criterion, run)
      AcceptanceCriterion.new(
        id: criterion.id, claim: criterion.claim, evaluator: criterion.evaluator,
        run: run, target: criterion.target, required: criterion.required,
        scope: criterion.scope, freshness: criterion.freshness, owner: criterion.owner,
        risk_class: criterion.risk_class,
        provenance: discovery[:"#{criterion.id}_command"]&.provenance
      )
    end

    # Owner-declared acceptance checks become criteria owned by the repository.
    # A criterion that edits CI/verifier surfaces is elevated by policy.
    def declared_criteria
      checks = declared&.acceptance&.dig(:checks) || []
      checks.map do |check|
        AcceptanceCriterion.new(
          id: check[:id] || "declared-#{check.object_id}",
          claim: check[:claim] || "Owner-declared check #{check[:id]}.",
          evaluator: check[:evaluator] || :command,
          run: check[:run], target: check[:target],
          required: check.fetch(:required, true),
          owner: "repository",
          risk_class: check[:risk_class] || :normal
        )
      end
    end

    def declared_protected_paths
      declared&.acceptance&.dig(:protected_paths) || []
    end

    def resolve_autonomy
      declared_autonomy = declared&.autonomy || {}
      DEFAULT_AUTONOMY.merge(declared_autonomy.transform_values(&:to_sym))
    end

    def resolve_security_posture
      declared_posture = declared&.security&.dig(:posture)
      return SecurityPosture[declared_posture] if declared_posture

      SecurityPosture[Frankenstein.configuration.security_posture]
    end
  end
end
