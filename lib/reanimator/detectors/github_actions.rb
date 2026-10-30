# frozen_string_literal: true

require "yaml"

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

      # The matrix keys a Ruby workflow uses for the interpreter it tests.
      RUBY_KEYS = %w[ruby ruby-version].freeze

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

      # One fact per workflow, holding every Ruby its jobs' matrices exercise.
      def ruby_matrix_facts(workflows)
        workflows.filter_map do |path|
          versions = matrix_versions(repository.read(path))
          next if versions.empty?

          fact(:ci_ruby_matrix, category: :support_matrix,
            claim: "CI exercises Ruby: #{versions.join(", ")}.",
            value: versions, confidence: :high, source: path, method: :yaml_matrix, detail: versions.join(", "))
        end
      end

      # Every Ruby named in a job's strategy.matrix - its list and its
      # include: entries - read as YAML, so comments and exclude: entries are
      # simply not evidence, and each value is kept as the workflow wrote it
      # (truffleruby+graalvm, 3.4.0-preview1, ...). A pinned ruby-version on a
      # single job (a lint job, say) is not a support matrix and is not read.
      # A workflow that does not parse yields nothing rather than a guess.
      def matrix_versions(body)
        jobs = parse(body)&.dig("jobs")
        return [] unless jobs.is_a?(Hash)

        jobs.values.flat_map { |job| job_rubies(job) }.uniq
      end

      def job_rubies(job)
        matrix = job.is_a?(Hash) ? job.dig("strategy", "matrix") : nil
        return [] unless matrix.is_a?(Hash)

        includes = Array(matrix["include"]).grep(Hash)
        (rubies_in(matrix) + includes.flat_map { |entry| rubies_in(entry) }).map { |value| ruby_label(value) }
      end

      def rubies_in(hash) = RUBY_KEYS.flat_map { |key| Array(hash[key]) }

      # Actions renders a YAML number the way JSON would: 3.0 becomes "3",
      # which setup-ruby reads as the latest 3.x - so a whole float is a bare
      # major, not 3.0.
      def ruby_label(value)
        (value.is_a?(Float) && value == value.floor) ? value.to_i.to_s : value.to_s
      end

      def parse(body)
        body && YAML.safe_load(body, aliases: true)
      rescue Psych::Exception
        nil
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
