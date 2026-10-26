# frozen_string_literal: true

module Reanimator
  # A category of maintenance work with a default autonomy posture per rung
  # (specification section 11, "Default autonomy by task class"). The table is
  # deliberately conservative: security remediation may repair and submit, but
  # major upgrades only plan, verifier changes demand elevated review, and
  # nothing merges automatically.
  class TaskClass
    # Per-rung default policy tokens used in the section 11 table.
    #   :auto        run automatically
    #   :allowed     permitted when the rung is enabled
    #   :draft       permitted, but only as a draft PR
    #   :draft_elevated  draft PR plus elevated review
    #   :plan_only   may only produce a plan
    #   :issue       may only open an issue
    #   :optional    permitted but not default
    #   :by_exception only when explicitly excepted
    #   :off         not permitted
    attr_reader :key, :title, :defaults, :elevated_review

    def initialize(key:, title:, defaults:, elevated_review: false)
      @key = key
      @title = title
      @defaults = defaults
      @elevated_review = elevated_review
      freeze
    end

    def elevated_review? = @elevated_review

    def default_for(level) = defaults.fetch(level.to_sym, :off)

    def self.fetch(key)
      ALL.fetch(key.to_sym) { raise UnknownError, "Unknown task class #{key.inspect}. Known: #{ALL.keys.join(", ")}." }
    end

    def self.keys = ALL.keys

    def self.build(key, title, observe:, diagnose:, repair:, submit:, merge:, elevated_review: false)
      new(key: key, title: title, elevated_review: elevated_review,
        defaults: {observe: observe, diagnose: diagnose, repair: repair, submit: submit, merge: merge})
    end

    ALL = {
      critical_security: build(:critical_security, "Critical security remediation",
        observe: :auto, diagnose: :auto, repair: :allowed, submit: :allowed, merge: :off),
      patch_dependency: build(:patch_dependency, "Patch dependency update",
        observe: :auto, diagnose: :auto, repair: :allowed, submit: :allowed, merge: :off),
      minor_dependency: build(:minor_dependency, "Minor dependency update",
        observe: :auto, diagnose: :auto, repair: :allowed, submit: :draft, merge: :off),
      major_upgrade: build(:major_upgrade, "Major dependency or runtime update",
        observe: :auto, diagnose: :auto, repair: :plan_only, submit: :issue, merge: :off),
      mechanical_formatting: build(:mechanical_formatting, "Mechanical formatting",
        observe: :auto, diagnose: :auto, repair: :optional, submit: :draft, merge: :off),
      behavioral_refactor: build(:behavioral_refactor, "Behavioral refactor",
        observe: :auto, diagnose: :auto, repair: :by_exception, submit: :draft, merge: :off),
      verifier_modification: build(:verifier_modification, "CI or verifier modification",
        observe: :auto, diagnose: :auto, repair: :by_exception, submit: :draft_elevated, merge: :off,
        elevated_review: true)
    }.freeze
  end
end
