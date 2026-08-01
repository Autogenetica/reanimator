# frozen_string_literal: true

module Frankenstein
  # The registry of built-in vitality profiles. These are the "reusable
  # bundles of obligations for a common project shape" from section 02, seeded
  # with the ecosystems the specification prioritizes for v1 (Ruby and Rails,
  # section 20). Each profile's criteria are *defaults*: discovery fills in the
  # actual commands a repository uses, and anything a profile expects but
  # discovery cannot find is surfaced as missing proof rather than assumed.
  module Profiles
    module_function

    # @param id [Symbol, String]
    # @return [VitalityProfile]
    # @raise [UnknownError] when no such profile is registered
    def fetch(id)
      all.fetch(id.to_sym) do
        raise UnknownError, "Unknown vitality profile #{id.inspect}. Known: #{all.keys.join(", ")}."
      end
    end

    def registered?(id) = all.key?(id.to_sym)

    def ids = all.keys

    # @return [Hash{Symbol=>VitalityProfile}]
    def all
      @all ||= build.freeze
    end

    # Convenience for building a criterion with profile-friendly defaults.
    def criterion(id, claim, evaluator:, run: nil, target: nil, required: true, risk_class: :normal)
      AcceptanceCriterion.new(
        id: id, claim: claim, evaluator: evaluator, run: run, target: target,
        required: required, owner: "profile", risk_class: risk_class
      )
    end

    def build
      {
        generic: VitalityProfile.new(
          id: :generic,
          summary: "Any repository: documented, licensed, and readable.",
          criteria: [
            criterion(:documented, "Project has a README.", evaluator: :documentation_check, target: "README", required: false),
            criterion(:licensed, "Project declares a license.", evaluator: :documentation_check, target: "LICENSE", required: false)
          ]
        ),
        "ruby-gem": VitalityProfile.new(
          id: :"ruby-gem",
          summary: "A published Ruby gem: resolves, tests, lints, and builds.",
          criteria: [
            criterion(:dependencies, "Dependencies resolve.", evaluator: :command, run: "bundle check"),
            criterion(:tests, "Test suite passes.", evaluator: :command, run: "bundle exec rake spec"),
            criterion(:lint, "Lint passes.", evaluator: :command, run: "bundle exec standardrb", required: false),
            criterion(:build, "Gem builds.", evaluator: :command, run: "gem build *.gemspec"),
            criterion(:support_matrix, "Declared Ruby versions are exercised.", evaluator: :support_matrix, required: false)
          ]
        ),
        "ruby-cli": VitalityProfile.new(
          id: :"ruby-cli",
          summary: "A Ruby command-line tool: everything a gem needs plus a runnable executable.",
          inherits: [:"ruby-gem"],
          criteria: [
            criterion(:executable, "Executable boots and answers --help.", evaluator: :command, required: false)
          ]
        ),
        "web-application": VitalityProfile.new(
          id: :"web-application",
          summary: "A deployable web application that must boot and answer a health endpoint.",
          criteria: [
            criterion(:boot, "Application boots and answers its health endpoint.", evaluator: :http_smoke, target: "/up")
          ]
        ),
        "rails-app": VitalityProfile.new(
          id: :"rails-app",
          summary: "A maintained Rails application: tests, assets, and boot.",
          inherits: [:"web-application"],
          criteria: [
            criterion(:tests, "Test suite passes.", evaluator: :command, run: "bin/rails test"),
            criterion(:assets, "Frontend assets build.", evaluator: :command, run: "yarn build", required: false)
          ]
        ),
        "rails-legacy": VitalityProfile.new(
          id: :"rails-legacy",
          summary: "A historical Rails application preserved for readability and provenance.",
          criteria: [
            criterion(:"source-readable", "Source remains readable with intact history.", evaluator: :repository_integrity),
            criterion(:"reproduction-documented", "Reproduction instructions are documented.", evaluator: :documentation_check, target: "README")
          ]
        ),
        "maintained-fork": VitalityProfile.new(
          id: :"maintained-fork",
          summary: "A maintained fork tracked for upstream divergence and unique commits.",
          criteria: [
            criterion(:divergence, "Unique commits and upstream divergence are known.", evaluator: :repository_integrity, required: false)
          ]
        ),
        "constrained-hardware": VitalityProfile.new(
          id: :"constrained-hardware",
          summary: "A hardware- or credential-dependent project verified within declared boundaries.",
          criteria: [
            criterion(:"unit-tests", "Unit tests pass on hosted runners.", evaluator: :command, run: "bundle exec rake test"),
            criterion(:"package-build", "Package builds.", evaluator: :command, run: "gem build *.gemspec")
          ]
        )
      }
    end
  end
end
