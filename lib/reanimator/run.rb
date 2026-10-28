# frozen_string_literal: true

require "time"

module Reanimator
  # An immutable record of one stewardship attempt (specification section 17 run
  # ledger). A run captures its trigger, objective, policy version, agent, the
  # access it used, its evidence, and its outcome - the auditable story of what
  # Reanimator did and why. Outcomes are drawn from the section 17 vocabulary:
  # a healthy no-op, a report, a draft PR, an escalation, or a safe stop.
  class Run
    OUTCOMES = %i[no_op report draft_pr escalation safe_stop].freeze

    attr_reader :outcome, :repository, :policy_version, :trigger, :objective,
      :provider, :access, :pre_state, :post_state, :cost_usd, :proposed_change, :reason, :pull_request_url,
      :generated_at

    def initialize(outcome:, repository:, policy_version:, trigger:, objective: nil, provider: nil,
      access: {}, pre_state: nil, post_state: nil, cost_usd: 0.0, proposed_change: nil, reason: nil,
      pull_request_url: nil, now: nil)
      @outcome = outcome.to_sym
      @repository = repository
      @policy_version = policy_version
      @trigger = trigger
      @objective = objective
      @provider = provider
      @access = access
      @pre_state = pre_state
      @post_state = post_state
      @cost_usd = cost_usd
      @proposed_change = proposed_change
      @reason = reason
      @pull_request_url = pull_request_url
      @generated_at = now || Time.now
      raise UnknownError, "Unknown run outcome #{outcome.inspect}." unless OUTCOMES.include?(@outcome)
    end

    # Repair alone never writes: a proposed draft PR is an artifact. Only an
    # explicitly armed and permitted submission writes, and then only a branch
    # and a draft pull request on the remote - never the local working tree.
    def submitted? = !pull_request_url.nil?

    def wrote_to_repository? = submitted?

    def to_h
      {
        outcome: outcome, repository: repository.full_name, policy_version: policy_version,
        trigger: trigger, objective: objective&.id, provider: provider, access: access,
        pre_state: pre_state, post_state: post_state, cost_usd: cost_usd,
        reason: reason, proposed_change: proposed_change&.to_h, pull_request_url: pull_request_url,
        generated_at: generated_at.iso8601
      }.compact
    end
  end
end
