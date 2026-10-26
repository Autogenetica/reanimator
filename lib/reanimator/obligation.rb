# frozen_string_literal: true

module Reanimator
  # A bounded unit of drift or risk that must be verified, repaired, accepted,
  # deferred, or waived (specification section 02 and section 17). An obligation
  # is idempotent and deduplicated by repository, policy, target, and drift
  # condition, so the same failing criterion does not spawn a swarm of tasks.
  class Obligation
    STATES = %i[open in_progress resolved deferred waived].freeze

    attr_reader :repository, :policy_version, :target, :trigger, :urgency, :task_class, :state

    def initialize(repository:, policy_version:, target:, trigger:, task_class:, urgency: :normal, state: :open)
      @repository = repository
      @policy_version = policy_version
      @target = target
      @trigger = trigger
      @task_class = task_class
      @urgency = urgency
      @state = state
    end

    # Stable identity used for idempotent deduplication (section 17).
    def id
      "#{repository.full_name}::#{policy_version}::#{target.id}"
    end

    def to_h
      {
        id: id, repository: repository.full_name, policy_version: policy_version,
        target: target.id, trigger: trigger, task_class: task_class, urgency: urgency, state: state
      }
    end
  end
end
