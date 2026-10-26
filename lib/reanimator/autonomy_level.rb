# frozen_string_literal: true

module Reanimator
  # One rung of the autonomy ladder (specification section 11): trust grows one
  # bounded capability at a time, from read-only observation to narrowly bounded
  # merge authority. Each rung names the behavior it allows and the GitHub
  # access it requires, so a permission grant can always be tied to the exact
  # action it enables.
  class AutonomyLevel
    attr_reader :key, :rank, :behavior, :github_access

    def initialize(key:, rank:, behavior:, github_access:)
      @key = key
      @rank = rank
      @behavior = behavior
      @github_access = github_access
      freeze
    end

    def to_sym = key

    # The ladder in ascending order of authority.
    LADDER = [
      [:observe, "Inventory, detect drift, and report.", "Metadata and read-only contents."],
      [:diagnose, "Run sandboxed checks and produce plans.", "Read-only plus ephemeral execution."],
      [:repair, "Create a bounded patch in an isolated workspace.", "No repository write required until submission."],
      [:submit, "Create or update a branch and pull request.", "Contents and pull-request write for selected repositories."],
      [:merge, "Merge explicitly eligible changes through branch rules.", "Merge capability only where GitHub and policy allow."],
      [:release, "Publish packages or deploy.", "Not part of the initial product promise."]
    ].each_with_index.each_with_object({}) do |((key, behavior, access), index), all|
      all[key] = new(key: key, rank: index, behavior: behavior, github_access: access)
    end.freeze

    def self.fetch(key)
      LADDER.fetch(key.to_sym) { raise UnknownError, "Unknown autonomy level #{key.inspect}." }
    end

    # @return [Array<Symbol>] the ladder keys in ascending authority
    def self.keys = LADDER.keys
  end
end
