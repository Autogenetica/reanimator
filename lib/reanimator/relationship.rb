# frozen_string_literal: true

module Reanimator
  # A typed edge between two repositories (specification section 10). Related
  # projects are a compatibility graph, not isolated automation targets, so an
  # edge is a first-class value: it names *what kind* of dependence exists, and
  # it is what a family failure points at - "the exact edge that broke, not
  # merely the repository that ran CI".
  class Relationship
    TYPES = {
      compatibility_suite: "A separate executable suite that validates this project's public claims.",
      plugin_for: "An integration that must remain compatible with a host project or SDK.",
      deployment_example: "A deployment example that must build against its parent project.",
      portfolio_index: "An index or profile that should reflect active project metadata.",
      shared_library: "A package whose releases trigger downstream compatibility checks.",
      fork_of: "A maintained fork whose unique commits and upstream divergence matter.",
      documentation_for: "Documentation whose examples and links must stay synchronized."
    }.freeze

    # The member role each downstream relationship implies.
    ROLES = {
      compatibility_suite: :compatibility_suite,
      plugin_for: :plugin,
      deployment_example: :deployment_example,
      portfolio_index: :index,
      shared_library: :library,
      fork_of: :fork,
      documentation_for: :documentation
    }.freeze

    # @return [String] the downstream repository (the dependent side)
    attr_reader :from
    # @return [String] the upstream repository it depends on
    attr_reader :to
    # @return [Symbol] one of {TYPES}
    attr_reader :type
    # @return [String, nil] why this edge is believed
    attr_reader :evidence

    def initialize(from:, to:, type:, evidence: nil)
      @type = type.to_sym
      unless TYPES.key?(@type)
        raise UnknownError, "Unknown relationship type #{type.inspect}. Known: #{TYPES.keys.join(", ")}."
      end

      @from = from
      @to = to
      @evidence = evidence
      freeze
    end

    def description = TYPES.fetch(type)

    # The role the dependent side plays inside its family.
    def role = ROLES.fetch(type, :member)

    # A single, unambiguous name for this edge - what a family failure reports.
    def label = "#{to} -> #{from} (#{type.to_s.tr("_", " ")})"

    def to_h = {from: from, to: to, type: type, evidence: evidence}.compact
  end
end
