# frozen_string_literal: true

module Reanimator
  module Detectors
    # Detects high-value proof-of-life evaluators (specification section 06:
    # Operational proof and Contracts). Health endpoints, doctor commands, and
    # smoke scripts are the cheapest, most trustworthy evidence that software
    # actually runs, so they are called out for promotion into acceptance
    # criteria.
    class OperationalProof < Base
      SMOKE_SCRIPTS = ["bin/smoke", "bin/doctor", "script/smoke", "bin/health"].freeze
      HEALTH_ROUTE = %r{(get\s+['"]/(up|health|healthz)['"]|/up\b)}

      def detect
        facts = []

        if (script = SMOKE_SCRIPTS.find { |s| repository.exist?(s) })
          facts << fact(:smoke_script, category: :operational_proof,
            claim: "A smoke/doctor script is available: #{script}.",
            value: script, confidence: :high, source: script, method: :file_present)
        end

        if health_endpoint?
          facts << fact(:health_endpoint, category: :operational_proof,
            claim: "Exposes a health endpoint suitable for a boot smoke test.",
            confidence: :medium, source: "routes/config", method: :regex_match)
        end

        if repository.exist?("examples") || repository.any?("examples/**/*")
          facts << fact(:examples, category: :contracts,
            claim: "Ships runnable examples that can back behavioral claims.",
            confidence: :medium, source: "examples/", method: :file_present)
        end

        facts
      end

      private

      def health_endpoint?
        candidates = repository.glob("config/routes.rb") +
          repository.glob("config.ru") +
          repository.glob("app.rb")
        candidates.any? { |path| repository.read(path).to_s.match?(HEALTH_ROUTE) }
      end
    end
  end
end
