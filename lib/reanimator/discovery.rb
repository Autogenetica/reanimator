# frozen_string_literal: true

module Reanimator
  # Runs every detector over a repository and collects their discovered facts
  # (specification section 06). Discovery is strictly read-only and never
  # decides policy: it produces proposals, each with provenance and confidence,
  # for a human to confirm during contract review.
  class Discovery
    # The default detector set, ordered roughly ecosystem-first so that later
    # reporting reads naturally.
    DEFAULT_DETECTORS = [
      Detectors::Bundler,
      Detectors::RubyGem,
      Detectors::RailsApp,
      Detectors::Commands,
      Detectors::GitHubActions,
      Detectors::SecurityControls,
      Detectors::Fork,
      Detectors::OperationalProof,
      Detectors::Relationships
    ].freeze

    attr_reader :repository, :detectors

    def initialize(repository, detectors: DEFAULT_DETECTORS)
      @repository = repository
      @detectors = detectors
    end

    # @return [DiscoveryResult]
    def run
      facts = detectors.flat_map do |klass|
        klass.new(repository).call
      rescue => e
        # A misbehaving detector must never sink the whole observation; record
        # the failure and keep going. Robustness over completeness here - but the
        # failure is logged with its class and origin so a swallowed bug stays
        # diagnosable rather than silently dropping facts.
        Reanimator.logger.warn(
          "#{klass} failed on #{repository.name}: #{e.class}: #{e.message} (at #{e.backtrace&.first})"
        )
        []
      end

      DiscoveryResult.new(repository: repository, facts: facts)
    end
  end
end
