# frozen_string_literal: true

require "time"

module Frankenstein
  # Configuration drift across a whole portfolio (section 06 applied to the
  # portfolio of section 04). One repository's drift is a question; a
  # portfolio's is a triage list, so the entries sort themselves into what
  # needs a human, what changed harmlessly, what is unchanged, and what was
  # never recorded in the first place.
  #
  # A portfolio run is never stopped by one bad member: a repository that
  # cannot be read, or whose snapshot cannot be parsed, becomes a failed entry
  # and the rest still report.
  class PortfolioDrift
    # One repository's outcome. `report` is nil when nothing has been recorded
    # for that repository yet, which is a finding in its own right rather than
    # a quiet pass.
    Entry = Struct.new(:name, :report, :snapshot, :recorded_to, :error) do
      # Compare one repository against whatever the store has on record. The
      # entry builds itself because it is the thing that knows its own shape -
      # both a portfolio scan and a single-repository run want exactly this.
      #
      # @param path [String] a repository root on disk
      # @param store [SnapshotStore]
      # @param record [Boolean] write the current snapshot after comparing
      # @param intent [Symbol, nil]
      # @return [Entry]
      def self.for(path, store:, record: false, intent: nil)
        repository = Repository.at(path)
        repository.intent = intent if intent
        current = ContractSnapshot.of(EffectivePolicyResolver.new(repository).resolve)
        # Loaded before anything is written, so recording and comparing in one
        # pass still compares against what was previously on record.
        previous = store.load(repository)

        new(
          name: repository.full_name,
          report: previous && DriftDetector.between(previous, current),
          snapshot: current,
          recorded_to: (store.save(current, repository) if record)
        )
      rescue Frankenstein::Error => e
        new(name: File.basename(File.expand_path(path)), error: e.message)
      end

      def failed? = !error.nil?

      def recorded? = !report.nil?

      def requires_review? = recorded? && report.requires_review?

      def drifted? = recorded? && report.drifted?

      # Changed, but only in ways that prove the same or more than before.
      def benign? = drifted? && !requires_review?

      def unchanged? = recorded? && !drifted?

      # Nothing to compare against: not a pass, just an absence.
      def unrecorded? = !recorded? && !failed?
    end

    # @param paths [Array<String>] repository roots on disk
    # @param store [SnapshotStore]
    # @param record [Boolean] write each repository's current snapshot
    # @param intent [Symbol, nil] override the inferred lifecycle intent
    # @return [PortfolioDrift]
    def self.scan(paths, store: SnapshotStore.new, record: false, intent: nil, name: "portfolio")
      entries = Array(paths).map { |path| Entry.for(path, store: store, record: record, intent: intent) }
      new(entries: entries, name: name, store: store)
    end

    attr_reader :entries, :name, :store, :generated_at

    def initialize(entries:, name: "portfolio", store: SnapshotStore.new, generated_at: nil)
      @entries = entries
      @name = name
      @store = store
      @generated_at = generated_at || Time.now
    end

    def policy_changed = entries.select(&:requires_review?)

    def benign = entries.select(&:benign?)

    def unchanged = entries.select(&:unchanged?)

    def unrecorded = entries.select(&:unrecorded?)

    def failed = entries.select(&:failed?)

    # Whether anything in the portfolio asks for a human - what a CI gate keys
    # off. Benign change does not count, and nor does a repository with nothing
    # recorded yet: that is a known first-run state the report names plainly.
    # A repository whose snapshot could not be *read* does count. "We could not
    # tell" is not "nothing changed", and corrupting a snapshot file must never
    # be a way to pass.
    def requires_review? = policy_changed.any? || failed.any?

    def to_h
      {
        portfolio: name,
        generated_at: generated_at.iso8601,
        requires_review: requires_review?,
        tally: {
          policy_changed: policy_changed.size, benign: benign.size,
          unchanged: unchanged.size, unrecorded: unrecorded.size, failed: failed.size
        },
        repositories: entries.map { |entry| entry_hash(entry) }
      }
    end

    private

    def entry_hash(entry)
      {repository: entry.name, error: entry.error, drift: entry.report&.to_h}.compact
    end
  end
end
