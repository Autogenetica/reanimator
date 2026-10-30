# frozen_string_literal: true

require "shellwords"

module Reanimator
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
          assets_command,
          executable_command
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

      # A gem's shipped executable proves it boots by answering --help. Only
      # exe/ counts: bin/ holds developer scripts, not product surface. Dotfiles
      # (.DS_Store, .gitkeep) and files without the executable bit are not
      # executables, and the path is shell-escaped because it comes from the
      # repository and is run through `sh -c`.
      def executable_command
        return unless first_path("*.gemspec")

        exe = shipped_executable
        return unless exe

        command(:executable_command, "#{executable_runner} #{Shellwords.escape(exe)} --help",
          claim: "The shipped executable #{exe} answers --help.", source: exe, confidence: :high)
      end

      def shipped_executable
        repository.glob("exe/*").sort.find do |path|
          !File.basename(path).start_with?(".") && File.file?(repository.absolute(path)) && executable?(path)
        end
      end

      # In a git checkout, executable means committed with mode 100755 - what a
      # clone in CI will have - not whatever the local filesystem bit says. A
      # tree without git (such as an export of HEAD) carries the committed modes
      # on disk, so the filesystem bit is the answer there.
      def executable?(path)
        return File.executable?(repository.absolute(path)) unless Git.repository?(repository.path)

        Git.capture(repository.path, "ls-files", "-s", "--", path).to_s.start_with?("100755 ")
      end

      # Without a Gemfile there is no bundle to load the gem through, so put
      # its own lib/ on the load path instead.
      def executable_runner
        repository.exist?("Gemfile") ? "bundle exec" : "ruby -Ilib"
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
