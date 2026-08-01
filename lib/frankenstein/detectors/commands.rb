# frozen_string_literal: true

module Frankenstein
  module Detectors
    # Discovers the commands a repository already uses to prove itself
    # (specification section 06: Commands). The point is that users should
    # "confirm facts rather than transcribe their own CI" - so this detector
    # reads Rakefiles, lint configuration, gemspecs, and package.json scripts
    # and reports the install/test/lint/build commands it finds. Each command
    # fact later overrides the matching profile default (section 00: reuse
    # detected checks; surface missing proof).
    class Commands < Base
      def detect
        [
          dependencies_command,
          test_command,
          lint_command,
          build_command,
          assets_command
        ].compact
      end

      private

      def dependencies_command
        return unless repository.exist?("Gemfile")

        command(:dependencies_command, "bundle check",
          claim: "Dependency resolution is verified with `bundle check`.",
          source: "Gemfile")
      end

      def test_command
        if rspec?
          command(:test_command, "bundle exec rspec",
            claim: "Tests run with RSpec.", source: rspec_source, confidence: :high)
        elsif repository.exist?("test") || repository.any?("test/**/*_test.rb")
          command(:test_command, "bundle exec rake test",
            claim: "Tests run with the default rake test task.", source: "test/")
        elsif (script = package_script("test"))
          command(:test_command, script,
            claim: "Tests run via the package.json test script.", source: "package.json")
        end
      end

      def lint_command
        if repository.exist?(".standard.yml") || gemfile_mentions?("standard")
          command(:lint_command, "bundle exec standardrb",
            claim: "Lint runs with Standard.", source: standard_source, confidence: :high)
        elsif repository.exist?(".rubocop.yml")
          command(:lint_command, "bundle exec rubocop",
            claim: "Lint runs with RuboCop.", source: ".rubocop.yml", confidence: :high)
        end
      end

      def build_command
        gemspec = first_path("*.gemspec")
        return unless gemspec

        command(:build_command, "gem build #{gemspec}",
          claim: "Gem builds with `gem build`.", source: gemspec, confidence: :high)
      end

      def assets_command
        script = package_script("build")
        return unless script

        command(:assets_command, script,
          claim: "Assets build via the package.json build script.", source: "package.json")
      end

      # --- helpers -------------------------------------------------------------

      def command(key, value, claim:, source:, confidence: :medium)
        fact(key, category: :commands, claim: claim, value: value,
          confidence: confidence, source: source, method: :command_inference, detail: value)
      end

      def rspec?
        repository.exist?(".rspec") || repository.exist?("spec") || repository.any?("spec/**/*_spec.rb")
      end

      def rspec_source
        repository.exist?(".rspec") ? ".rspec" : "spec/"
      end

      def standard_source
        repository.exist?(".standard.yml") ? ".standard.yml" : "Gemfile"
      end

      def gemfile_mentions?(gem)
        body = repository.read("Gemfile").to_s + repository.read("Gemfile.lock").to_s
        body.include?(gem)
      end

      def package_script(name)
        body = repository.read("package.json")
        return unless body

        require "json"
        scripts = JSON.parse(body).fetch("scripts", {})
        script = scripts[name]
        return unless script

        # Prefer the yarn/npm indirection so the discovered command is portable.
        repository.exist?("yarn.lock") ? "yarn #{name}" : "npm run #{name}"
      rescue JSON::ParserError
        nil
      end
    end
  end
end
