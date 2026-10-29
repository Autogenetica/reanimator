# frozen_string_literal: true

module Reanimator
  module Reports
    # Renders the result of `reanimator submit` (section 11 submit rung). It
    # says what was written to GitHub and what was not - including a branch
    # pushed before a pull request could be opened - and closes with the
    # promises submission keeps.
    class Submission
      def initialize(proposal, outcome)
        @proposal = proposal
        @outcome = outcome
      end

      def render
        lines = ["Submission — #{@proposal.slug}", "Outcome:  #{label}", "Base:     #{@proposal.base[0, 12]} (verified)"]
        lines << "Pull request: #{@outcome.url}" if @outcome.submitted?
        lines << "Reason:   #{@outcome.reason}" unless @outcome.submitted?
        lines << "Branch:   #{@proposal.branch} (#{@outcome.branch_written? ? "written" : "not written"})"
        lines << "Files:    #{@proposal.paths.join(", ")}"
        lines << "NOTHING WAS MERGED. NO REPOSITORY CODE RAN IN THIS PROCESS."
        lines.join("\n")
      end

      private

      def label
        return "DRAFT PR OPENED" if @outcome.submitted?

        @outcome.branch_written? ? "NOT SUBMITTED (branch written, no pull request)" : "NOT SUBMITTED"
      end
    end
  end
end
