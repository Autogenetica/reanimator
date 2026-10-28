# frozen_string_literal: true

module Reanimator
  module Reports
    # Renders a run ledger entry (specification section 17). It leads with the
    # outcome, records the agent and policy version, and - for a proposed repair
    # - shows the draft PR that was produced but not submitted, reaffirming that
    # no source was written.
    class Run
      OUTCOME_LABEL = {
        no_op: "NO-OP (healthy)",
        report: "REPORT",
        draft_pr: "DRAFT PR (proposed, not submitted)",
        escalation: "ESCALATION",
        safe_stop: "SAFE STOP"
      }.freeze

      def initialize(run)
        @run = run
      end

      def outcome_label
        return "DRAFT PR (submitted)" if @run.submitted?

        OUTCOME_LABEL.fetch(@run.outcome, @run.outcome.to_s.upcase)
      end

      # The promise the run kept, stated last. A submission wrote a branch and a
      # draft pull request on the remote and nothing else.
      def closing
        return "NO SOURCE WAS WRITTEN TO THE REPOSITORY." unless @run.submitted?

        "SUBMITTED AS A DRAFT PULL REQUEST. THE LOCAL WORKING TREE WAS NOT MODIFIED; NOTHING WAS MERGED."
      end

      def render
        lines = [
          "Run — #{@run.repository.full_name}",
          "Outcome:  #{outcome_label}",
          "Trigger:  #{@run.trigger}",
          "Policy:   #{@run.policy_version}"
        ]
        lines << "Objective: #{@run.objective.id} — #{@run.objective.claim}" if @run.objective
        lines << "Agent:    #{@run.provider}" if @run.provider
        lines << "Evidence: #{@run.pre_state} → #{@run.post_state}" if @run.post_state
        lines << "Reason:   #{@run.reason}" if @run.reason
        lines.concat(proposed_change_lines) if @run.proposed_change
        lines << closing
        lines.join("\n")
      end

      private

      def proposed_change_lines
        change = @run.proposed_change
        [
          "",
          @run.submitted? ? "Draft PR: #{@run.pull_request_url}" : "Proposed draft PR:",
          "  branch: #{change.branch}",
          "  title:  #{change.title}",
          "  files:  #{change.patch.paths.join(", ")}"
        ]
      end
    end
  end
end
