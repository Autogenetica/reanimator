# frozen_string_literal: true

module Reanimator
  module Evaluators
    # A native evaluator for preserve/legacy repositories: attests that source
    # remains readable with intact history. It only inspects git metadata, so
    # it runs even in the non-executing baseline - a preserved artifact can be
    # proven readable without running a single line of its code.
    class RepositoryIntegrity < Base
      def call
        metadata = repository.metadata
        if metadata.has_git?
          result(:verified,
            detail: "Git history is intact (#{metadata.commit_count || "unknown"} commits, " \
                    "last activity #{metadata.last_activity&.strftime("%Y-%m-%d") || "unknown"}).")
        else
          result(:missing_evidence, detail: "No git history found; source integrity cannot be attested.")
        end
      end
    end
  end
end
