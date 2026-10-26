# frozen_string_literal: true

module Reanimator
  # Assembles the acceptance criteria for one repository out of the layers
  # allowed to contribute them (specification section 07). Three layers speak:
  # the vitality profile's defaults, the security posture's obligations, and
  # the owner's declared checks. They are *merged*, not concatenated, so a
  # layer naming an existing criterion id replaces it rather than arguing with
  # it twice in the same report - and the owner's declaration wins.
  #
  # This is deliberately not part of {EffectivePolicyResolver}: resolving the
  # precedence stack and assembling the list of things to prove change for
  # different reasons, and adding a fourth layer should not mean reopening the
  # resolver.
  class CriteriaStack
    def initialize(profile:, posture:, discovery:, declared:)
      @profile = profile
      @posture = posture
      @discovery = discovery
      @declared = declared
    end

    # @return [Array<AcceptanceCriterion>]
    def resolve
      merge(profile_criteria, security_criteria, declared_criteria)
    end

    private

    attr_reader :profile, :posture, :discovery, :declared

    # Keeps each criterion in the position it first appeared, so reports stay
    # stable, while the last layer to claim an id supplies the criterion.
    def merge(*layers)
      layers.flatten.each_with_object({}) { |criterion, merged| merged[criterion.id] = criterion }.values
    end

    # Profile criteria, with discovered commands substituted in for the
    # matching defaults (section 00: reuse detected checks; surface missing
    # proof).
    def profile_criteria
      commands = discovery.discovered_commands
      profile.resolved_criteria.map do |criterion|
        run = commands[criterion.id]
        run ? with_run(criterion, run) : criterion
      end
    end

    def with_run(criterion, run)
      AcceptanceCriterion.new(
        id: criterion.id, claim: criterion.claim, evaluator: criterion.evaluator,
        run: run, target: criterion.target, required: criterion.required,
        scope: criterion.scope, freshness: criterion.freshness, owner: criterion.owner,
        risk_class: criterion.risk_class,
        provenance: discovery.command_fact(criterion.id)&.provenance
      )
    end

    # The security evidence the posture makes binding (section 12). These are
    # policy-owned rather than profile-owned: how much security proof a
    # repository must show is a posture decision, not a question of what shape
    # the project happens to be.
    def security_criteria
      posture.obligations.map do |control_id, required|
        control = SecurityControl.fetch(control_id)
        AcceptanceCriterion.new(
          id: control.criterion_id, claim: control.claim,
          evaluator: :security_evidence, target: control.to_s,
          required: required, owner: "policy"
        )
      end
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
  end
end
