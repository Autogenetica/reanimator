# frozen_string_literal: true

module Frankenstein
  module Evaluators
    # Runs a discovered or declared shell command and grades it by exit status.
    # In the default (non-executing) mode it reports what it *would* run, so a
    # user can see the plan before granting execution. When execution is
    # enabled the command is bounded by a hard timeout.
    class Command < Base
      def call
        return result(:missing_evidence, detail: "No command discovered for this check.") unless criterion.run

        unless execute
          return result(:planned, detail: "Would run: #{criterion.run}")
        end

        outcome = BoundedCommand.run(criterion.run, chdir: repository.path, timeout: timeout)
        grade(outcome)
      end

      private

      def grade(outcome)
        if outcome.timed_out?
          result(:failed, detail: "Timed out after #{timeout}s: #{criterion.run}", duration: outcome.duration)
        elsif outcome.success?
          result(:verified, detail: criterion.run, evidence: tail(outcome.output), duration: outcome.duration)
        else
          result(:failed, detail: "Nonzero exit: #{criterion.run}", evidence: tail(outcome.output), duration: outcome.duration)
        end
      end
    end
  end
end
