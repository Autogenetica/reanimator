# frozen_string_literal: true

require "tmpdir"
require "fileutils"

module Reanimator
  module Commissioning
    # Builds a disposable fixture repository with a single, seeded defect
    # (specification section 08 step 2: "run a synthetic repair against a
    # disposable fixture repository"). The fixture ships an addition helper that
    # wrongly subtracts and a required check that fails because of it, plus a
    # protected verifier file the agent must not touch. Nothing here depends on
    # Bundler, so commissioning is fast and hermetic.
    module Fixture
      BUGGY_LIB = <<~RUBY
        # frozen_string_literal: true

        module Calc
          module_function

          def add(a, b)
            a - b
          end
        end
      RUBY

      CHECK = <<~RUBY
        # frozen_string_literal: true

        require "calc"

        raise "add(2, 2) should be 4, got \#{Calc.add(2, 2)}" unless Calc.add(2, 2) == 4
        puts "ok"
      RUBY

      CONTRACT = <<~YAML
        version: 1
        intent: maintain
        profile: generic
        acceptance:
          protected_paths:
            - check.rb
          checks:
            - id: arithmetic
              claim: "add(2, 2) equals 4."
              run: "ruby -Ilib check.rb"
              required: true
      YAML

      module_function

      # @return [String] path to a fresh disposable fixture
      def build
        dir = Dir.mktmpdir("reanimator-commission")
        write(dir, "lib/calc.rb", BUGGY_LIB)
        write(dir, "check.rb", CHECK)
        write(dir, ".reanimator.yml", CONTRACT)
        write(dir, "README.md", "# Commissioning fixture\n")
        dir
      end

      def write(dir, relative, contents)
        full = File.join(dir, relative)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, contents)
      end
    end
  end
end
