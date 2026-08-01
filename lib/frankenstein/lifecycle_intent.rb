# frozen_string_literal: true

module Frankenstein
  # The first and most important configuration value (specification section
  # 05). Lifecycle intent is the owner's declaration of *why* a repository
  # should continue to exist and what level of care it deserves. The same
  # technical signal - say, a failing test - means different things for a
  # maintained product, a preserved artifact, and an ignored fork, so intent
  # is never inferred as final without confirmation.
  class LifecycleIntent
    # @return [Symbol] stable key used in contracts and reports
    attr_reader :key
    # @return [String] the promise Frankenstein makes for this intent
    attr_reader :promise
    # @return [String] the default activity this intent authorizes
    attr_reader :default_activity
    # @return [Boolean] whether the intent creates any stewardship obligation
    attr_reader :creates_obligation

    def initialize(key:, promise:, default_activity:, creates_obligation: true)
      @key = key
      @promise = promise
      @default_activity = default_activity
      @creates_obligation = creates_obligation
      freeze
    end

    # @return [Boolean] whether the intent creates any stewardship obligation
    def creates_obligation?
      @creates_obligation
    end

    # The canonical intents, keyed by symbol. Order is meaningful for display:
    # most-active first, dormant last.
    ALL = {
      maintain: new(
        key: :maintain,
        promise: "Keep the repository runnable, supported, secure, and within its declared contract.",
        default_activity: "Scheduled verification and eligible repair."
      ),
      monitor: new(
        key: :monitor,
        promise: "Detect meaningful deterioration without routine code churn.",
        default_activity: "Periodic checks and event-triggered diagnosis."
      ),
      preserve: new(
        key: :preserve,
        promise: "Protect historical readability, provenance, and known reproduction instructions.",
        default_activity: "Link, license, metadata, and optional reproducibility checks."
      ),
      incubate: new(
        key: :incubate,
        promise: "Surface missing foundations while the project is still becoming real.",
        default_activity: "Report gaps; avoid unsolicited modernization."
      ),
      retire: new(
        key: :retire,
        promise: "Make end-of-life explicit and safely reduce obligations.",
        default_activity: "Archive checklist, notices, migration path, and access cleanup."
      ),
      upstream: new(
        key: :upstream,
        promise: "Track a fork's divergence and upstream movement.",
        default_activity: "Compare ancestry and unique commits; no generic dependency churn."
      ),
      ignore: new(
        key: :ignore,
        promise: "Create no stewardship obligation.",
        default_activity: "No scheduled activity.",
        creates_obligation: false
      )
    }.freeze

    # @param key [Symbol, String]
    # @return [LifecycleIntent]
    # @raise [UnknownError] when the key is not a canonical intent
    def self.fetch(key)
      ALL.fetch(key.to_sym) do
        raise UnknownError, "Unknown lifecycle intent #{key.inspect}. Known: #{ALL.keys.join(", ")}."
      end
    end

    # @param key [Symbol, String]
    # @return [Boolean]
    def self.valid?(key)
      ALL.key?(key.to_sym)
    end

    def to_sym = key

    def to_s = key.to_s
  end
end
