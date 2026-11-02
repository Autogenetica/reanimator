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
      failures = []
      facts = detectors.flat_map do |klass|
        klass.new(repository).call
      rescue StandardError, SystemStackError => e
        # A misbehaving detector must never sink the whole observation; record
        # the failure and keep going. Its facts are missing, not absent, so the
        # failure travels with the result: an evaluator that reads "no fact" as
        # "nothing declared" would otherwise pass on a detector that crashed.
        Reanimator.logger.warn(
          "#{klass} failed on #{repository.name}: #{e.class}: #{e.message} (at #{e.backtrace&.first})"
        )
        failures << DiscoveryResult::Failure.new(detector: klass, error: "#{e.class}: #{e.message}")
        []
      end

      DiscoveryResult.new(repository: repository, facts: facts, failures: failures)
    end
  end
end
