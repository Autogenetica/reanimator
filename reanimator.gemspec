# frozen_string_literal: true

require_relative "lib/reanimator/version"

Gem::Specification.new do |spec|
  spec.name = "reanimator"
  spec.version = Reanimator::VERSION
  spec.authors = ["Valentino Stoll"]
  spec.email = ["v@codenamev.com"]

  spec.summary = "Turn repository intent into a verified, low-friction stewardship contract."
  spec.description = <<~DESC.tr("\n", " ").strip
    Reanimator reads a repository, infers what "healthy" means for it, and
    proves that health without changing a single line of code. It classifies
    lifecycle intent, discovers a vitality contract from evidence, resolves an
    effective policy, and produces a read-only proof-of-life baseline - before
    any coding agent or write permission is ever involved.
  DESC
  spec.homepage = "https://github.com/codenamev/reanimator"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/codenamev/reanimator"
  spec.metadata["changelog_uri"] = "https://github.com/codenamev/reanimator/tree/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # The `git ls-files -z` loads the files in the RubyGem that have been added
  # into git, mirroring the convention used across the codenamev portfolio.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ spec/ features/ .git .github .architecture Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime: a quiet, self-contained toolchain. Zeitwerk loads the library;
  # Thor and the tty-* stack power the interactive CLI but are only paid for
  # when the CLI is actually invoked (see lib/reanimator.rb).
  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "tty-table", "~> 0.12"
  spec.add_dependency "tty-box", "~> 0.7"

  # Bundled gems that Ruby is trimming from the default set - declare what we use.
  spec.add_dependency "psych", ">= 5.0"
  spec.add_dependency "logger"
end
