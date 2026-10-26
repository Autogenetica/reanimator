# frozen_string_literal: true

module Reanimator
  module Detectors
    # Detects that a repository is packaged as a Ruby gem (specification
    # section 06: Ecosystem). A gemspec is the single strongest signal that the
    # ruby-gem vitality profile applies, so this fact is high-confidence and
    # names the gemspec as its evidence.
    class RubyGem < Base
      def detect
        gemspec = first_path("*.gemspec")
        return [] unless gemspec

        facts = [
          fact(:ruby_gem, category: :ecosystem,
            claim: "Packaged and released as a Ruby gem.",
            confidence: :high, source: gemspec, method: :file_present)
        ]

        if (exe = executables).any?
          facts << fact(:executables, category: :operational_proof,
            claim: "Ships command-line executable(s): #{exe.join(", ")}.",
            value: exe, confidence: :high, source: exe.first, method: :file_present)
        end

        facts
      end

      private

      # Executables shipped in exe/ or bin/ (excluding the developer scripts
      # bundler generates - setup and console are not product surface).
      def executables
        (repository.glob("exe/*") + repository.glob("bin/*"))
          .reject { |p| %w[bin/setup bin/console].include?(p) }
          .select { |p| File.file?(repository.absolute(p)) }
      end
    end
  end
end
