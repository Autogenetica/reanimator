# frozen_string_literal: true

module Frankenstein
  module Evaluators
    # A native evaluator that checks for the presence of documentation the
    # criterion names (README, LICENSE, or any target prefix). Cheap, read-only,
    # and always runnable - it backs the "reproduction-documented" and
    # "documented/licensed" criteria without executing anything.
    class DocumentationCheck < Base
      KNOWN = {"README" => "README*", "LICENSE" => "LICENSE*"}.freeze

      def call
        target = criterion.target || "README"
        pattern = KNOWN.fetch(target, "#{target}*")
        matches = repository.glob(pattern)

        if matches.any?
          result(:verified, detail: "Found #{matches.first}.")
        else
          result(:missing_evidence, detail: "No #{target} found.")
        end
      end
    end
  end
end
