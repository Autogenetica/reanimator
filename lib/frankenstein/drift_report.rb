# frozen_string_literal: true

module Frankenstein
  # What changed between two contract snapshots, and which of those changes a
  # human has to look at (specification section 06).
  #
  # The distinction the specification insists on is not "big" versus "small" -
  # it is *policy* versus *benign*. A renamed test command is benign: the
  # obligation is unchanged, only its spelling moved. A removed security gate
  # or a narrowed runtime matrix is a policy change: less is being proven than
  # before, and nobody necessarily decided that on purpose. Drift detection
  # earns its keep by never burying the second kind in a list of the first.
  class DriftReport
    # A single difference between two snapshots. It carries its own severity
    # and the sentence explaining why it has that severity, so no caller has
    # to re-derive the judgement in order to display it.
    class Change
      attr_reader :subject, :kind, :from, :to, :severity, :explanation

      def initialize(subject:, kind:, severity:, explanation:, from: nil, to: nil)
        @subject = subject
        @kind = kind
        @severity = severity
        @explanation = explanation
        @from = from
        @to = to
        freeze
      end

      def policy? = severity == :policy

      def benign? = severity == :benign

      # A single line naming the difference.
      def summary
        case kind
        when :added then "#{subject} added: #{to}"
        when :removed then "#{subject} removed: #{from}"
        else "#{subject}: #{from} → #{to}"
        end
      end

      def to_h
        {subject: subject, kind: kind, from: from, to: to, severity: severity, explanation: explanation}
      end
    end

    attr_reader :repository, :previous, :current, :changes

    def initialize(repository:, previous:, current:, changes:)
      @repository = repository
      @previous = previous
      @current = current
      @changes = changes
      freeze
    end

    def policy_changes = changes.select(&:policy?)

    def benign_changes = changes.select(&:benign?)

    def drifted? = changes.any?

    # Whether a human has to look. Benign drift is reported but does not
    # demand attention; policy drift always does.
    def requires_review? = policy_changes.any?

    def since = previous.taken_at

    def to_h
      {
        repository: repository,
        since: since.is_a?(Time) ? since.iso8601 : since,
        drifted: drifted?,
        requires_review: requires_review?,
        policy_changes: policy_changes.map(&:to_h),
        benign_changes: benign_changes.map(&:to_h)
      }
    end
  end
end
