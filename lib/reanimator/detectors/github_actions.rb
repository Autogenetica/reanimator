# frozen_string_literal: true

module Reanimator
  module Detectors
    # Reads .github/workflows/*.yml for the evidence CI already provides
    # (specification section 06: Commands, Support matrix, Security controls,
    # Operational proof). Reanimator's job is to surface what a maintainer
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

      # Inline matrices (ruby: ["3.3", "3.4"]) and YAML block lists
      # (ruby:\n  - "3.3"\n  - "3.4").
      RUBY_MATRIX = /ruby(?:-version)?\s*:\s*\[([^\]]+)\]/
      RUBY_MATRIX_BLOCK = /ruby(?:-version)?\s*:[ \t]*\n((?:[ \t]*-[ \t]*[^\n]+\n?)+)/
      # A single Ruby on one line - an include: entry or a setup-ruby input.
      RUBY_SCALAR = /^[ \t-]*ruby(?:-version)?\s*:\s*["']?([^"'\s\[\]{}$]+)["']?\s*$/
      # What a Ruby entry can be: a version, or a named interpreter build.
      RUBY_ENTRY = /\A(?:\d+(?:\.\d+)*|head|debug|(?:jruby|truffleruby|ruby)(?:-[\w.]+)?)\z/

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

      # One fact per workflow, holding every Ruby any of its jobs exercises - a
      # lint job pinned to one Ruby must not hide the test matrix beside it.
      def ruby_matrix_facts(workflows)
        workflows.filter_map do |path|
          body = repository.read(path)
          next unless body

          versions = matrix_versions(body)
          next if versions.empty?

          fact(:ci_ruby_matrix, category: :support_matrix,
            claim: "CI exercises Ruby: #{versions.join(", ")}.",
            value: versions, confidence: :high, source: path, method: :yaml_matrix, detail: versions.join(", "))
        end
      end

      # An entry must look like a Ruby, so a list of steps after an empty key
      # is not read as versions.
      def matrix_versions(body)
        live = uncommented(body)
        inline = live.scan(RUBY_MATRIX).flat_map { |(list)| list.split(",") }
        block = live.scan(RUBY_MATRIX_BLOCK).flat_map { |(list)| list.lines.map { |line| line.sub(/\A\s*-\s*/, "") } }
        scalar = live.scan(RUBY_SCALAR).flatten
        (inline + block + scalar).map { |v| v.strip.delete("\"'") }.select { |v| RUBY_ENTRY.match?(v) }.uniq
      end

      # The workflow without comments: commented-out lines are not run, and
      # commenting a version out is how one is usually dropped.
      def uncommented(body)
        body.lines(chomp: true).reject { |line| line.lstrip.start_with?("#") }
          .map { |line| line.sub(/\s+#.*$/, "") }.join("\n")
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
