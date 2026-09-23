# frozen_string_literal: true

require "time"

module Frankenstein
  # Compares two contract snapshots and classifies every difference as either a
  # policy change or a benign one (specification section 06).
  #
  # The classification rule is one question asked of each difference: *is less
  # being proven than before?* A removed security gate, a narrowed runtime
  # matrix, a dropped required obligation, a widened autonomy grant and a fresh
  # waiver all answer yes, so they are policy changes and a human is asked to
  # look. A renamed test command, an added check, a withdrawn waiver and a
  # tightened matrix answer no - they are reported, but they do not interrupt
  # anyone.
  class DriftDetector
    # A severity plus the sentence that justifies it. Every change carries the
    # reasoning for its own classification, so nothing downstream has to guess
    # why a difference did or did not require review.
    Verdict = Struct.new(:severity, :explanation)

    # Every judgement this detector can make, gathered in one place: "why did
    # that need review?" is a question about policy, and the answer should not
    # be scattered through the code that happened to notice the difference.
    CHANGED_INTENT = Verdict.new(:policy, "A lifecycle decision changed; what the repository owes changes with it.")
    CHANGED_PROFILE = Verdict.new(:policy, "The vitality profile changed, so the whole definition of healthy moved.")
    CHANGED_POSTURE = Verdict.new(:policy, "The security posture changed, altering how strictly findings are treated.")
    WIDENED_AUTONOMY = Verdict.new(:policy, "Autonomy was widened: the agent may now do more here than it could.")
    NARROWED_AUTONOMY = Verdict.new(:benign, "Autonomy was narrowed; the agent may do less than it could.")
    UNPROTECTED_PATH = Verdict.new(:policy, "A path lost its elevated review; changes there no longer need a human.")
    PROTECTED_PATH = Verdict.new(:benign, "More of the repository is protected than before.")
    NARROWED_MATRIX = Verdict.new(:policy, "The runtime matrix narrowed: a version that used to be exercised no longer is.")
    WIDENED_MATRIX = Verdict.new(:benign, "The runtime matrix widened; more versions are exercised.")
    REMOVED_CONTROL = Verdict.new(:policy, "A security gate was removed; it is no longer part of the proof.")
    ADDED_CONTROL = Verdict.new(:benign, "A security gate was added.")
    DROPPED_REQUIRED = Verdict.new(:policy, "A required obligation is gone; nothing proves it any more.")
    DROPPED_OPTIONAL = Verdict.new(:benign, "An optional check is gone.")
    ADDED_CRITERION = Verdict.new(:benign, "More is proven than before.")
    RELAXED_OBLIGATION = Verdict.new(:policy, "An obligation stopped blocking; failing it no longer holds anything back.")
    TIGHTENED_OBLIGATION = Verdict.new(:benign, "An obligation became blocking; more is required than before.")
    MOVED_EVALUATOR = Verdict.new(:policy, "The way this obligation is proven changed, so old and new evidence are not comparable.")
    # The specification's own example of drift that is *not* alarming: the
    # obligation is identical, only the command spelling moved.
    RENAMED_COMMAND = Verdict.new(:benign, "The same obligation is proven by a differently spelled command.")
    ADDED_WAIVER = Verdict.new(:policy, "An obligation is now accepted as risk instead of proven.")
    REMOVED_WAIVER = Verdict.new(:benign, "Accepted risk was withdrawn; the obligation is blocking again.")
    EXTENDED_WAIVER = Verdict.new(:policy, "Accepted risk was extended, so the exception outlives the decision that made it.")
    SHORTENED_WAIVER = Verdict.new(:benign, "Accepted risk was shortened.")
    # Everything else here fails closed; an expiry nobody can read is not
    # evidence that the risk got smaller, so it is not treated as if it were.
    UNREADABLE_WAIVER = Verdict.new(:policy, "Accepted risk moved to an expiry that cannot be read, so it cannot be shown to be shorter.")

    # Scalar fields whose value simply must not change unnoticed.
    SCALAR_RULES = {
      intent: CHANGED_INTENT,
      profile: CHANGED_PROFILE,
      security_posture: CHANGED_POSTURE
    }.freeze

    # How one set-valued part of a snapshot drifts. Membership changes are the
    # same shape everywhere - something is in the old set, or the new one, or
    # both - so the only thing that varies is what each direction means.
    SetRule = Struct.new(:field, :subject, :on_removed, :on_added)

    SET_RULES = [
      SetRule.new(:protected_paths, "protected path", UNPROTECTED_PATH, PROTECTED_PATH),
      SetRule.new(:support_matrix, "supported runtime", NARROWED_MATRIX, WIDENED_MATRIX),
      SetRule.new(:security_controls, "security control", REMOVED_CONTROL, ADDED_CONTROL)
    ].freeze

    # One comparable field of a criterion that both snapshots record. Whether
    # the difference matters can depend on its direction, so each rule judges
    # its own before/after rather than exposing a severity outright.
    CriterionRule = Struct.new(:field, :subject, :judge) do
      def verdict(before, after) = judge.call(before, after)
    end

    CRITERION_RULES = [
      CriterionRule.new(:required, "required", ->(before, _after) { before ? RELAXED_OBLIGATION : TIGHTENED_OBLIGATION }),
      CriterionRule.new(:evaluator, "evaluator", ->(_before, _after) { MOVED_EVALUATOR }),
      CriterionRule.new(:run, "command", ->(_before, _after) { RENAMED_COMMAND })
    ].freeze

    # Autonomy is a grant, not a scale: anything other than :disabled is a
    # grant, and :automatic grants it without a human in the loop.
    AUTONOMY_RANKS = {disabled: 0, manual: 1, proposal: 1, automatic: 2}.freeze

    # @param previous [ContractSnapshot] the contract as last recorded
    # @param current [ContractSnapshot] the contract the evidence resolves to now
    # @return [DriftReport]
    def self.between(previous, current) = new(previous, current).call

    def initialize(previous, current)
      @previous = previous
      @current = current
    end

    def call
      ensure_same_repository

      DriftReport.new(
        repository: @current.repository, previous: @previous, current: @current,
        changes: scalar_changes + autonomy_changes + set_changes + criteria_changes + waiver_changes
      )
    end

    private

    # Comparing two different repositories' snapshots would produce a report
    # that reads plausibly and means nothing, and the dangerous direction is
    # "no drift" - quietly reporting a repository unchanged that was never
    # recorded. A git origin names a repository exactly, so it decides whenever
    # both snapshots carry one; without it the recorded names are the only
    # evidence there is, and two same-named local checkouts are
    # indistinguishable.
    def ensure_same_repository
      recorded, current = identities
      return if recorded.nil? || current.nil? || recorded == current

      raise ContractError,
        "Snapshot is for #{recorded}, not #{current}; drift is only meaningful within one repository."
    end

    def identities
      if @previous.origin && @current.origin
        [@previous.origin, @current.origin]
      else
        [@previous.repository, @current.repository]
      end
    end

    def scalar_changes
      SCALAR_RULES.filter_map do |field, verdict|
        before = @previous.public_send(field)
        after = @current.public_send(field)
        next if before == after

        change(field.to_s.tr("_", " "), :changed, verdict, from: before, to: after)
      end
    end

    def autonomy_changes
      (@previous.autonomy.keys | @current.autonomy.keys).filter_map do |rung|
        before = @previous.autonomy[rung] || :disabled
        after = @current.autonomy[rung] || :disabled
        next if before == after

        verdict = (rank(after) > rank(before)) ? WIDENED_AUTONOMY : NARROWED_AUTONOMY
        change("autonomy #{rung}", :changed, verdict, from: before, to: after)
      end
    end

    def rank(mode) = AUTONOMY_RANKS.fetch(mode.to_sym, 1)

    def set_changes
      SET_RULES.flat_map do |rule|
        before = Array(@previous.public_send(rule.field))
        after = Array(@current.public_send(rule.field))

        (before - after).map { |value| change(rule.subject, :removed, rule.on_removed, from: value) } +
          (after - before).map { |value| change(rule.subject, :added, rule.on_added, to: value) }
      end
    end

    def criteria_changes
      before_ids = @previous.criterion_ids
      after_ids = @current.criterion_ids

      (before_ids - after_ids).map { |id| dropped_criterion(id) } +
        (after_ids - before_ids).map { |id| change("criterion", :added, ADDED_CRITERION, to: id) } +
        (before_ids & after_ids).flat_map { |id| altered_criterion(id) }
    end

    def dropped_criterion(id)
      verdict = @previous.requires?(id) ? DROPPED_REQUIRED : DROPPED_OPTIONAL
      change("criterion", :removed, verdict, from: id)
    end

    def altered_criterion(id)
      before = @previous.criterion(id)
      after = @current.criterion(id)

      CRITERION_RULES.filter_map do |rule|
        was = before[rule.field]
        now = after[rule.field]
        next if was == now

        change("criterion #{id} #{rule.subject}", :changed, rule.verdict(was, now), from: was, to: now)
      end
    end

    def waiver_changes
      before_targets = @previous.waiver_targets
      after_targets = @current.waiver_targets

      (after_targets - before_targets).map { |target| change("waiver", :added, ADDED_WAIVER, to: target) } +
        (before_targets - after_targets).map { |target| change("waiver", :removed, REMOVED_WAIVER, from: target) } +
        (before_targets & after_targets).filter_map { |target| rescheduled_waiver(target) }
    end

    def rescheduled_waiver(target)
      before = @previous.waiver_expiry(target)
      after = @current.waiver_expiry(target)
      return if before == after

      change("waiver #{target} expiry", :changed, expiry_verdict(before, after),
        from: before || "open-ended", to: after || "open-ended")
    end

    # An open-ended waiver (no expiry) outlives every dated one.
    def expiry_verdict(before, after)
      return EXTENDED_WAIVER if after.nil?
      return SHORTENED_WAIVER if before.nil?

      (Time.parse(after) > Time.parse(before)) ? EXTENDED_WAIVER : SHORTENED_WAIVER
    rescue ArgumentError, TypeError
      UNREADABLE_WAIVER
    end

    def change(subject, kind, verdict, from: nil, to: nil)
      DriftReport::Change.new(
        subject: subject, kind: kind, from: from, to: to,
        severity: verdict.severity, explanation: verdict.explanation
      )
    end
  end
end
