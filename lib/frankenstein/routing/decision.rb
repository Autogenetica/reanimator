# frozen_string_literal: true

module Frankenstein
  module Routing
    # The outcome of routing one task to one profile (specification section 08).
    # A decision is never silent: it carries the human-readable explanation the
    # spec insists on ("Selected Codex because ... Amp was excluded because
    # ...") and the declared fallbacks - fallback is never implied.
    class Decision
      attr_reader :profile, :strategy, :explanation, :excluded, :fallbacks

      def initialize(profile:, strategy:, explanation:, excluded: [], fallbacks: [])
        @profile = profile
        @strategy = strategy
        @explanation = explanation
        @excluded = excluded
        @fallbacks = fallbacks
      end

      def selected? = !profile.nil?

      def provider = profile&.provider

      def to_h
        {
          strategy: strategy,
          selected: provider,
          explanation: explanation,
          fallbacks: fallbacks.map(&:provider),
          excluded: excluded
        }
      end
    end
  end
end
