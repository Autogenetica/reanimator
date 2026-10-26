# frozen_string_literal: true

module Reanimator
  # Materializes an {EffectiveContract} from the precedence stack in section
  # 07. For this read-only slice the layers that participate are the product
  # safety floor (non-bypassable), the repository contract (owner declarations
  # in .reanimator.yml), and runtime discovery (detected commands and
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
      posture = resolve_security_posture

      EffectiveContract.new(
        repository: repository,
        intent: intent,
        intent_confirmed: intent_confirmed,
        profile: profile,
        profile_source: profile_source,
        criteria: CriteriaStack.new(
          profile: profile, posture: posture, discovery: discovery, declared: declared
        ).resolve,
        discovery: discovery,
        security_posture: posture,
        autonomy: autonomy,
        protected_paths: SafetyFloor.protected_paths(declared_protected_paths),
        waivers: build_waivers,
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

    def declared_protected_paths
      declared&.acceptance&.dig(:protected_paths) || []
    end

    # Owner-declared waivers become accepted-risk exceptions on the contract.
    def build_waivers
      (declared&.waivers || []).map do |waiver|
        Waiver.new(
          target: waiver[:target] || waiver[:id],
          reason: waiver[:reason].to_s,
          owner: waiver[:owner] || "repository",
          scope: waiver[:scope] || {},
          expires: waiver[:expires]
        )
      end
    end

    def resolve_autonomy
      declared_autonomy = declared&.autonomy || {}
      DEFAULT_AUTONOMY.merge(declared_autonomy.transform_values(&:to_sym))
    end

    def resolve_security_posture
      declared_posture = declared&.security&.dig(:posture)
      return SecurityPosture[declared_posture] if declared_posture

      SecurityPosture[Reanimator.configuration.security_posture]
    end
  end
end
