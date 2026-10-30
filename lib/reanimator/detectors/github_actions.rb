# frozen_string_literal: true

require "date"
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
      # Past this many matrix combinations, exclude: entries are applied by
      # value alone rather than combination by combination.
      MAX_COMBINATIONS = 1_000

      def detect
        workflows = (repository.glob(".github/workflows/*.yml") + repository.glob(".github/workflows/*.yaml"))
          .select { |path| File.file?(repository.absolute(path)) }
        return [] if workflows.empty?

        facts = [
          fact(:ci_github_actions, category: :operational_proof,
            claim: "Continuous integration runs on GitHub Actions.",
            value: workflows, confidence: :high, source: workflows.first, method: :file_present)
        ]

        facts.concat(ruby_matrix_facts(workflows))
        facts.concat(unreadable_facts(workflows))
        facts.concat(security_facts(workflows))
        facts
      end

      private

      # One fact per workflow, holding every Ruby its jobs' matrices exercise.
      # A single job's pinned Ruby is not read: a lint or release job pinned to
      # one version cannot stand in for the tests, and from the workflow alone
      # there is no telling which job is which.
      def ruby_matrix_facts(workflows)
        workflows.filter_map do |path|
          jobs, = read(path)
          versions = Array(jobs).flat_map { |job| matrix_rubies(job) }.uniq
          next if versions.empty?

          fact(:ci_ruby_matrix, category: :support_matrix,
            claim: "CI exercises Ruby: #{versions.join(", ")}.",
            value: versions, confidence: :high, source: path, method: :yaml_matrix, detail: versions.join(", "))
        end
      end

      # Workflows Reanimator could not read, and why, so a missing matrix is
      # reported as its gap rather than as untested support.
      def unreadable_facts(workflows)
        workflows.filter_map do |path|
          _jobs, reason = read(path)
          next unless reason

          fact(:ci_workflow_unreadable, category: :support_matrix,
            claim: "#{path} could not be read: #{reason}.", value: reason,
            confidence: :high, source: path, method: :yaml_matrix, detail: reason)
        end
      end

      # The workflow's jobs, read as YAML, or nil and the reason it could not
      # be read. YAML aliases are refused - a workflow is repository input, and
      # an alias bomb would be expanded while reading it - and so is nesting
      # deep enough to exhaust the stack. Dates and symbols are read the way
      # the contract file reads them.
      def read(path)
        @read ||= {}
        @read[path] ||= begin
          document = YAML.safe_load(repository.read(path).to_s, permitted_classes: [Date, Time, Symbol], aliases: false)
          jobs = document.is_a?(Hash) ? document["jobs"] : nil
          [jobs.is_a?(Hash) ? jobs.values.grep(Hash) : []]
        rescue Psych::BadAlias
          [nil, "it uses YAML aliases, which Reanimator does not expand"]
        rescue Psych::Exception, SystemStackError => e
          [nil, "it is not valid YAML (#{e.class.name.split("::").last})"]
        end
      end

      # Every Ruby a job's strategy.matrix actually runs: its Ruby list less
      # whatever exclude: removes, plus include: entries - the order Actions
      # applies them in. Values are kept as the workflow wrote them.
      def matrix_rubies(job)
        matrix = job.dig("strategy", "matrix")
        return [] unless matrix.is_a?(Hash)

        key = RUBY_KEYS.find { |candidate| matrix.key?(candidate) }
        listed = key ? surviving(matrix, key, scalars(matrix[key])) : []
        (listed + included_rubies(matrix)).map { |value| ruby_label(value) }
      end

      # Whether the exclusions can be read as data. One written as an
      # expression is only known while the workflow runs, so it could remove
      # any Ruby; crediting the list anyway would fail open.
      def opaque_exclusions?(matrix)
        excludes = matrix["exclude"]
        return false if excludes.nil?
        return true unless excludes.is_a?(Array)

        excludes.any? { |entry| !entry.is_a?(Hash) || entry.values.any? { |v| v.is_a?(String) && v.include?("${{") } }
      end

      def included_rubies(matrix)
        Array(matrix["include"]).grep(Hash).flat_map { |entry| RUBY_KEYS.flat_map { |key| scalars(entry[key]) } }
      end

      # The rubies at least one surviving combination still runs.
      def surviving(matrix, key, rubies)
        return [] if opaque_exclusions?(matrix)

        excludes = Array(matrix["exclude"]).grep(Hash)
        return rubies if excludes.empty?

        others = matrix.except(key, "include", "exclude").transform_values { |values| Array(values) }
        if others.values.reduce(rubies.size) { |count, values| count * values.size } > MAX_COMBINATIONS
          excluded = excludes.flat_map { |entry| scalars(entry[key]) }.map(&:to_s)
          return rubies.reject { |ruby| excluded.include?(ruby.to_s) }
        end

        rubies.select do |ruby|
          combinations(others).any? do |combination|
            combination = combination.merge(key => ruby)
            excludes.none? { |entry| entry.all? { |k, v| combination[k].to_s == v.to_s } }
          end
        end
      end

      def combinations(dimensions)
        dimensions.reduce([{}]) do |combos, (name, values)|
          combos.product(values).map { |combo, value| combo.merge(name => value) }
        end
      end

      # Only strings and numbers are Rubies; anything else in a matrix is not,
      # and neither is an expression such as ${{ matrix.ruby }}, whose value
      # only exists while the workflow runs.
      def scalars(value)
        Array(value).select { |item| item.is_a?(Numeric) || (item.is_a?(String) && !item.include?("${{")) }
      end

      # Actions renders a YAML number the way JSON would: 3.0 becomes "3",
      # which setup-ruby reads as the latest 3.x - so a whole float is a bare
      # major, not 3.0.
      def ruby_label(value)
        (value.is_a?(Float) && value == value.floor) ? value.to_i.to_s : value.to_s
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
