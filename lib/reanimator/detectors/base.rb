# frozen_string_literal: true

module Reanimator
  module Detectors
    # Base class for every detector. A detector reads a repository through the
    # read-only helpers on {Repository} and returns an array of
    # {DiscoveredFact}s, each carrying its own provenance and confidence. It
    # never decides policy - it only proposes facts for a human to confirm.
    class Base
      # @return [Repository]
      attr_reader :repository

      def initialize(repository)
        @repository = repository
      end

      # @return [Array<DiscoveredFact>]
      def call
        detect
      end

      # @return [Array<DiscoveredFact>]
      def detect
        raise NotImplementedError, "#{self.class} must implement #detect"
      end

      private

      # Builds a discovered fact with a provenance record in one call - the
      # shape every detector uses.
      def fact(key, category:, claim:, source:, method:, value: true, confidence: :medium, detail: nil)
        DiscoveredFact.new(
          key: key,
          category: category,
          claim: claim,
          value: value,
          confidence: confidence,
          provenance: Provenance.new(source: source, method: method, detail: detail)
        )
      end

      # Convenience: the first repository-relative path matching any of the
      # given globs, or nil.
      def first_path(*patterns)
        patterns.flat_map { |pattern| repository.glob(pattern) }.first
      end
    end
  end
end
