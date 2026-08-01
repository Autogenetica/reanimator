# frozen_string_literal: true

module Frankenstein
  # The proof-of-life states a repository can hold (specification section 15).
  # These make "healthy silence" visible: Alive is an earned, evidence-backed
  # status, not the absence of alarms, and Unproven is never allowed to masquerade
  # as green.
  class RepositoryState
    attr_reader :key, :meaning, :color

    def initialize(key:, meaning:, color:)
      @key = key
      @meaning = meaning
      @color = color
      freeze
    end

    def to_sym = key

    def to_s = key.to_s

    # @return [Boolean] whether this state counts as verified vitality
    def alive? = key == :alive

    ALL = {
      alive: new(key: :alive, color: :green,
        meaning: "All due obligations have fresh passing evidence and no unapproved blocking risk."),
      at_risk: new(key: :at_risk, color: :yellow,
        meaning: "A deadline, support window, vulnerability, or degrading signal requires attention soon."),
      needs_you: new(key: :needs_you, color: :magenta,
        meaning: "A decision, permission, secret, environment, or domain judgment blocks safe progress."),
      recovering: new(key: :recovering, color: :cyan,
        meaning: "A repair or coordinated migration is active."),
      unproven: new(key: :unproven, color: :yellow,
        meaning: "A claim exists but sufficient executable evidence is absent or stale."),
      sleeping: new(key: :sleeping, color: :blue,
        meaning: "The repository is intentionally monitored or preserved rather than actively maintained."),
      diverged: new(key: :diverged, color: :magenta,
        meaning: "A maintained fork has meaningful upstream drift or unique commits requiring review."),
      retired: new(key: :retired, color: :white,
        meaning: "End-of-life is explicit and its retirement checklist is complete.")
    }.freeze

    def self.fetch(key)
      ALL.fetch(key.to_sym) { raise UnknownError, "Unknown repository state #{key.inspect}." }
    end
  end
end
