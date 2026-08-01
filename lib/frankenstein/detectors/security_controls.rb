# frozen_string_literal: true

module Frankenstein
  module Detectors
    # Detects repository-level security controls that live outside CI
    # (specification section 06: Security controls). A SECURITY.md, a
    # Dependabot configuration, or a CODEOWNERS file are all existing evidence
    # that should be credited rather than re-requested during onboarding.
    class SecurityControls < Base
      EVIDENCE = {
        security_policy: {
          globs: ["SECURITY.md", ".github/SECURITY.md", "docs/SECURITY.md"],
          claim: "A security policy is published (SECURITY.md)."
        },
        dependabot: {
          globs: [".github/dependabot.yml", ".github/dependabot.yaml"],
          claim: "Automated dependency updates are configured (Dependabot)."
        },
        codeowners: {
          globs: ["CODEOWNERS", ".github/CODEOWNERS", "docs/CODEOWNERS"],
          claim: "Ownership is declared (CODEOWNERS)."
        }
      }.freeze

      def detect
        EVIDENCE.filter_map do |key, spec|
          path = spec[:globs].find { |g| repository.exist?(g) }
          next unless path

          fact(key, category: :security_controls,
            claim: spec[:claim], confidence: :high, source: path, method: :file_present)
        end
      end
    end
  end
end
