# frozen_string_literal: true

module Frankenstein
  module Agents
    # The immutable envelope a repair must stay inside: which paths it may edit,
    # which are protected, what it may spend, and where code may travel.
    #
    # These four values always travel together, so they are one object rather
    # than a hash handed from caller to caller - and the decision that depends
    # on them ("may I edit this path?") lives here, with the data, instead of
    # being re-derived by whoever happens to hold the hash.
    class Constraints
      attr_reader :allowed_paths, :protected_paths, :max_cost_usd, :code_egress

      def initialize(allowed_paths: [], protected_paths: [], max_cost_usd: nil, code_egress: nil)
        @allowed_paths = Array(allowed_paths)
        @protected_paths = Array(protected_paths)
        @max_cost_usd = max_cost_usd
        @code_egress = code_egress
        freeze
      end

      # Accepts either a Constraints or the plain Hash shape, so callers may
      # pass whichever reads better at the call site.
      #
      # @param value [Constraints, Hash, nil]
      # @return [Constraints]
      def self.from(value)
        return value if value.is_a?(self)

        hash = value || {}
        new(
          allowed_paths: hash[:allowed_paths] || [],
          protected_paths: hash[:protected_paths] || [],
          max_cost_usd: hash[:max_cost_usd],
          code_egress: hash[:code_egress]
        )
      end

      # Whether a repository-relative path may be edited: never a protected
      # path, and inside the allowed set whenever one is declared. Matching is
      # depth-correct, so a protected `dir/**` cannot be evaded by nesting.
      def may_edit?(path)
        return false if SafetyFloor.protects?(path, protected_paths)

        allowed_paths.empty? || allowed_paths.any? { |glob| SafetyFloor.matches?(glob, path) }
      end

      def to_h
        {
          allowed_paths: allowed_paths, protected_paths: protected_paths,
          max_cost_usd: max_cost_usd, code_egress: code_egress
        }.compact
      end
    end
  end
end
