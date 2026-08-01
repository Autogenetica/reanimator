# frozen_string_literal: true

module Frankenstein
  module Detectors
    # Reads .github/workflows/*.yml for the evidence CI already provides
    # (specification section 06: Commands, Support matrix, Security controls,
    # Operational proof). Frankenstein's job is to surface what a maintainer
    # has already proven, so a project with a Ruby matrix and a
    # dependency-review action should never be asked to re-declare either.
    class GitHubActions < Base
      # Action fingerprints -> the security control they demonstrate.
      SECURITY_ACTIONS = {
        "actions/dependency-review-action" => "Dependency review",
        "github/codeql-action" => "CodeQL SAST",
        "gitleaks" => "Secret scanning (gitleaks)",
        "trufflehog" => "Secret scanning (trufflehog)",
        "brakeman" => "Brakeman SAST",
        "bundler-audit" => "Bundler dependency audit",
        "bundle audit" => "Bundler dependency audit"
      }.freeze

      RUBY_MATRIX = /ruby(?:-version)?\s*:\s*\[([^\]]+)\]/

      def detect
        workflows = repository.glob(".github/workflows/*.yml") + repository.glob(".github/workflows/*.yaml")
        return [] if workflows.empty?

        facts = [
          fact(:ci_github_actions, category: :operational_proof,
            claim: "Continuous integration runs on GitHub Actions.",
            value: workflows, confidence: :high, source: workflows.first, method: :file_present)
        ]

        facts.concat(ruby_matrix_facts(workflows))
        facts.concat(security_facts(workflows))
        facts
      end

      private

      def ruby_matrix_facts(workflows)
        workflows.filter_map do |path|
          body = repository.read(path)
          next unless body && (m = body.match(RUBY_MATRIX))

          versions = m[1].split(",").map { |v| v.strip.delete("\"'") }.reject(&:empty?)
          next if versions.empty?

          fact(:ci_ruby_matrix, category: :support_matrix,
            claim: "CI exercises Ruby: #{versions.join(", ")}.",
            value: versions, confidence: :high, source: path, method: :yaml_matrix, detail: versions.join(", "))
        end
      end

      def security_facts(workflows)
        text = workflows.map { |path| repository.read(path).to_s }.join("\n")
        SECURITY_ACTIONS.filter_map do |marker, description|
          next unless text.include?(marker)

          key = description.downcase.gsub(/[^a-z]+/, "_").gsub(/\A_|_\z/, "")
          fact(:"security_#{key}", category: :security_controls,
            claim: "Security control present: #{description}.",
            confidence: :high, source: ".github/workflows", method: :action_fingerprint, detail: marker)
        end
      end
    end
  end
end
