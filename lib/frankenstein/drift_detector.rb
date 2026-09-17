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

    # How one set-valued part of a snapshot drifts. Membership changes are the
    # same shape everywhere - something is in the old set, or the new one, or
    # both - so the only thing that varies is what each direction means.
    SetRule = Struct.new(:field, :subject, :on_removed, :on_added)

    SET_RULES = [
      SetRule.new(
        :protected_paths, "protected path",
        Verdict.new(:policy, "A path lost its elevated review; changes there no longer need a human."),
        Verdict.new(:benign, "More of the repository is protected than before.")
      ),
      SetRule.new(
        :support_matrix, "supported runtime",
        Verdict.new(:policy, "The runtime matrix narrowed: a version that used to be exercised no longer is."),
        Verdict.new(:benign, "The runtime matrix widened; more versions are exercised.")
      ),
      SetRule.new(
        :security_controls, "security control",
        Verdict.new(:policy, "A security gate was removed; it is no longer part of the proof."),
        Verdict.new(:benign, "A security gate was added.")
      )
    ].freeze

    # Scalar fields whose value simply must not change unnoticed.
    SCALAR_RULES = {
      intent: "A lifecycle decision changed; what the repository owes changes with it.",
      profile: "The vitality profile changed, so the whole definition of healthy moved.",
      security_posture: "The security posture changed, altering how strictly findings are treated."
    }.freeze

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
    # that reads plausibly and means nothing, so it is refused outright.
    def ensure_same_repository
      return if @previous.repository.nil? || @current.repository.nil?
      return if @previous.repository == @current.repository

      raise ContractError,
        "Snapshot is for #{@previous.repository}, not #{@current.repository}; drift is only meaningful within one repository."
    end

    def scalar_changes
      SCALAR_RULES.filter_map do |field, explanation|
        before = @previous.public_send(field)
        after = @current.public_send(field)
        next if before == after

        change(field.to_s.tr("_", " "), :changed, Verdict.new(:policy, explanation), from: before, to: after)
      end
    end

    def autonomy_changes
      (@previous.autonomy.keys | @current.autonomy.keys).filter_map do |rung|
        before = @previous.autonomy[rung] || :disabled
        after = @current.autonomy[rung] || :disabled
        next if before == after

        change("autonomy #{rung}", :changed, autonomy_verdict(before, after), from: before, to: after)
      end
    end

    def autonomy_verdict(before, after)
      if rank(after) > rank(before)
        Verdict.new(:policy, "Autonomy was widened: the agent may now do more here than it could.")
      else
        Verdict.new(:benign, "Autonomy was narrowed; the agent may do less than it could.")
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
        (after_ids - before_ids).map { |id| added_criterion(id) } +
        (before_ids & after_ids).flat_map { |id| altered_criterion(id) }
    end

    def dropped_criterion(id)
      verdict =
        if @previous.criterion(id)[:required]
          Verdict.new(:policy, "A required obligation is gone; nothing proves it any more.")
        else
          Verdict.new(:benign, "An optional check is gone.")
        end

      change("criterion", :removed, verdict, from: id)
    end

    def added_criterion(id)
      change("criterion", :added, Verdict.new(:benign, "More is proven than before."), to: id)
    end

    def altered_criterion(id)
      before = @previous.criterion(id)
      after = @current.criterion(id)

      [
        requirement_change(id, before, after),
        evaluator_change(id, before, after),
        command_change(id, before, after)
      ].compact
    end

    def requirement_change(id, before, after)
      return if before[:required] == after[:required]

      verdict =
        if before[:required]
          Verdict.new(:policy, "An obligation stopped blocking; failing it no longer holds anything back.")
        else
          Verdict.new(:benign, "An obligation became blocking; more is required than before.")
        end

      change("criterion #{id} required", :changed, verdict, from: before[:required], to: after[:required])
    end

    def evaluator_change(id, before, after)
      return if before[:evaluator] == after[:evaluator]

      change(
        "criterion #{id} evaluator", :changed,
        Verdict.new(:policy, "The way this obligation is proven changed, so old and new evidence are not comparable."),
        from: before[:evaluator], to: after[:evaluator]
      )
    end

    # The specification's own example of drift that is *not* alarming: the
    # obligation is identical, only the command spelling moved.
    def command_change(id, before, after)
      return if before[:run] == after[:run]

      change(
        "criterion #{id} command", :changed,
        Verdict.new(:benign, "The same obligation is proven by a differently spelled command."),
        from: before[:run], to: after[:run]
      )
    end

    def waiver_changes
      before_targets = @previous.waiver_targets
      after_targets = @current.waiver_targets

      (after_targets - before_targets).map { |target| added_waiver(target) } +
        (before_targets - after_targets).map { |target| removed_waiver(target) } +
        (before_targets & after_targets).filter_map { |target| rescheduled_waiver(target) }
    end

    def added_waiver(target)
      change(
        "waiver", :added,
        Verdict.new(:policy, "An obligation is now accepted as risk instead of proven."),
        to: target
      )
    end

    def removed_waiver(target)
      change(
        "waiver", :removed,
        Verdict.new(:benign, "Accepted risk was withdrawn; the obligation is blocking again."),
        from: target
      )
    end

    def rescheduled_waiver(target)
      before = expiry(@previous, target)
      after = expiry(@current, target)
      return if before == after

      verdict =
        if later?(after, before)
          Verdict.new(:policy, "Accepted risk was extended, so the exception outlives the decision that made it.")
        else
          Verdict.new(:benign, "Accepted risk was shortened.")
        end

      change("waiver #{target} expiry", :changed, verdict, from: before || "open-ended", to: after || "open-ended")
    end

    def expiry(snapshot, target)
      snapshot.waivers.find { |waiver| waiver[:target] == target }&.[](:expires)
    end

    # An open-ended waiver (no expiry) outlives every dated one.
    def later?(after, before)
      return false if after == before
      return true if after.nil?
      return false if before.nil?

      Time.parse(after) > Time.parse(before)
    rescue ArgumentError
      false
    end

    def change(subject, kind, verdict, from: nil, to: nil)
      DriftReport::Change.new(
        subject: subject, kind: kind, from: from, to: to,
        severity: verdict.severity, explanation: verdict.explanation
      )
    end
  end
end
