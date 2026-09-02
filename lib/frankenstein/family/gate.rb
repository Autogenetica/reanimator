# frozen_string_literal: true

module Frankenstein
  class Family
    # A cross-repository requirement (specification section 10 family policy):
    # when the `on` member is a candidate for change, a check in another member
    # must pass. Family policy may *add* evidence like this, but it can never
    # weaken a member repository's own security constraints.
    #
    # A gate with no explicit check falls back to the downstream member's own
    # proof command (a smoke script, else its discovered test command), so an
    # inferred family is useful without anyone writing YAML.
    class Gate
      # @return [String] the member whose change triggers this gate
      attr_reader :on
      # @return [String] the member that must prove itself
      attr_reader :requires_repository
      # @return [String, nil] the command to run, or nil to use the member's own
      attr_reader :check

      def initialize(on:, requires_repository:, check: nil)
        @on = on
        @requires_repository = requires_repository
        @check = check
        freeze
      end

      # Whether the check command must be resolved from the downstream member.
      def inferred_check? = check.nil?

      def label
        "#{on} requires #{check || "its own proof command"} in #{requires_repository}"
      end

      def to_h
        {on: on, require: {repository: requires_repository, check: check}.compact}
      end
    end
  end
end
