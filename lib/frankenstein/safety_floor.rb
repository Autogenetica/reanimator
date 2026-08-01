# frozen_string_literal: true

module Frankenstein
  # The product safety floor (specification section 07): the non-bypassable
  # bottom of the precedence stack. No layer above it - organization,
  # portfolio, family, repository, or task - may loosen these. The floor is
  # what makes the anti-gaming rule enforceable: "a task that modifies the
  # rules of proof cannot use those modified rules to approve itself."
  module SafetyFloor
    # Paths that always receive elevated scrutiny because editing them can
    # weaken a check, change who is trusted, or alter what "proof" means. A
    # repository contract may *add* to this set but never remove from it.
    PROTECTED_PATHS = [
      ".frankenstein.yml",
      ".github/workflows/**",
      ".github/dependabot.yml",
      "CODEOWNERS",
      ".github/CODEOWNERS"
    ].freeze

    # Merge is off in v1 regardless of what any layer requests (section 18:
    # automatic merge is explicitly later).
    MERGE_IN_V1 = :disabled

    module_function

    # The union of the floor's protected paths and any the contract declares.
    # @param declared [Array<String>]
    # @return [Array<String>]
    def protected_paths(declared = [])
      (PROTECTED_PATHS + Array(declared)).uniq
    end

    # Clamps an autonomy map so it can never exceed the floor. Returns the
    # clamped map plus a list of human-readable notes describing what was
    # tightened, so the resolver can surface the clamp rather than hide it.
    #
    # @param autonomy [Hash]
    # @return [Array(Hash, Array<String>)]
    def clamp_autonomy(autonomy)
      clamped = autonomy.dup
      notes = []

      if clamped[:merge] && clamped[:merge].to_sym != MERGE_IN_V1
        notes << "Merge autonomy was requested but is disabled by the v1 safety floor."
        clamped[:merge] = MERGE_IN_V1
      end
      clamped[:merge] ||= MERGE_IN_V1

      [clamped, notes]
    end

    # Verifier isolation is always on: evaluation runs separately from any
    # agent workspace, and an acting agent can never alter the effective
    # contract, hidden tests, or baseline evidence during an ordinary repair
    # (section 09). This is a constant, not a setting.
    def verifier_isolation? = true
  end
end
