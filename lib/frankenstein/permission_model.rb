# frozen_string_literal: true

module Frankenstein
  # Resolves what an agent is actually permitted to do for a task, by
  # intersecting the task class defaults (section 11) with the repository's
  # enabled autonomy (the effective contract) and the safety floor. The contract
  # is a *ceiling*: a task class may default to "submit as draft", but if the
  # repository has not enabled submit, the resolved action is off. Merge is
  # always off in v1.
  class PermissionModel
    # The resolved decision for one task against one contract.
    Resolution = Struct.new(:task_class, :actions, :elevated_review, :max_action) do
      def elevated_review? = elevated_review

      def permits?(level) = actions.fetch(level.to_sym, :off) != :off
    end

    def initialize(contract)
      @contract = contract
    end

    # @param task_class [Symbol, TaskClass]
    # @return [Resolution]
    def resolve(task_class)
      klass = task_class.is_a?(TaskClass) ? task_class : TaskClass.fetch(task_class)
      actions = AutonomyLevel.keys.each_with_object({}) do |level, resolved|
        resolved[level] = clamp(level, klass.default_for(level))
      end
      actions[:merge] = :off # safety floor: no automatic merge in v1

      Resolution.new(
        task_class: klass.key,
        actions: actions,
        elevated_review: klass.elevated_review? || touches_verifier?,
        max_action: highest_enabled(actions)
      )
    end

    private

    # Clamp a task-class default against what the contract enables for the rung.
    def clamp(level, default)
      return default if %i[observe diagnose].include?(level) # always at least observe/diagnose

      ceiling = @contract.autonomy[level]
      disabled?(ceiling) ? :off : default
    end

    def disabled?(ceiling)
      ceiling.nil? || ceiling.to_sym == :disabled
    end

    def touches_verifier?
      @contract.verifier_criteria.any?
    end

    def highest_enabled(actions)
      AutonomyLevel.keys.reverse.find { |level| actions[level] != :off } || :observe
    end
  end
end
