# frozen_string_literal: true

require "json"
require "open3"
require "timeout"

# Section 16: an escalation has to reach a human without anyone reading a
# terminal. The CLI's exit status carries it everywhere; inside GitHub Actions
# it also becomes one annotation per finding and a job-summary entry - and
# nothing the repository writes can forge or silence either.
# Subprocess specs must not inherit a real CI job's Actions variables.
QUIET_CI = {"GITHUB_ACTIONS" => nil, "GITHUB_STEP_SUMMARY" => nil}.freeze

RSpec.describe "escalation delivery" do
  def gem_with(requirement:, matrix: %w[3.3 3.4], workflow: nil)
    inline = matrix.map { |v| "\"#{v}\"" }.join(", ")
    {
      "Gemfile" => "gemspec\n",
      "widget.gemspec" => "Gem::Specification.new { |s| s.required_ruby_version = #{requirement} }\n",
      "README.md" => "# widget",
      ".github/workflows/ci.yml" => workflow || "jobs:\n  test:\n    strategy:\n      matrix:\n        ruby: [#{inline}]\n"
    }
  end

  def narrowed_support = gem_with(requirement: "'>= 3.1.0'")

  # The same repository, with the owner declaring narrowed support blocking.
  def blocking_support
    narrowed_support.merge(".reanimator.yml" => <<~YAML)
      version: 1
      acceptance:
        checks:
          - id: support_matrix
            claim: "Declared Ruby versions are exercised."
            evaluator: support_matrix
            required: true
    YAML
  end

  def support_result(files)
    Reanimator.baseline(make_repo(files: files)).result_for(:support_matrix)
  end

  describe Reanimator::Evaluators::SupportMatrix do
    it "treats a CI matrix that rose above the declared floor as missing evidence" do
      result = support_result(narrowed_support)

      expect(result.status).to eq(:missing_evidence)
      expect(result.detail).to include("Ruby 3.1.0 is declared supported, but CI's lowest Ruby is 3.3")
    end

    it "verifies a matrix that still reaches the declared floor, compared by minor release" do
      expect(support_result(gem_with(requirement: "'>= 3.3.0'"))).to be_verified
      expect(support_result(gem_with(requirement: "'>= 3.3.0'", matrix: %w[3.3.1 3.4]))).to be_verified
    end

    it "reads every matrix in every workflow, so a lint job cannot hide the test matrix" do
      files = gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(
        ".github/workflows/test.yml" => "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n"
      )
      expect(support_result(files)).to be_verified
    end

    it "reads YAML block-list matrices" do
      workflow = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby:\n          - \"3.1\"\n          - \"3.4\"\n"
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow))).to be_verified
    end

    it "finds the floor in >, array and Gem::Requirement forms" do
      ["'> 3.0'", "['>= 3.1', '< 4']", "Gem::Requirement.new('>= 3.1')"].each do |requirement|
        expect(support_result(gem_with(requirement: requirement)).status).to eq(:missing_evidence), requirement
      end
    end

    it "reads an exact = requirement as a floor" do
      expect(support_result(gem_with(requirement: "'= 3.1.0'")).status).to eq(:missing_evidence)
    end

    it "does not count commented-out matrix entries as tested" do
      workflow = "# ruby: [\"3.1\"]\njobs:\n  t:\n    strategy:\n      matrix:\n        # ruby: [\"3.1\", \"3.2\"]\n        ruby: [\"3.3\", \"3.4\"] # 3.1 dropped\n"
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow)).status).to eq(:missing_evidence)
    end

    it "does not read a bare major as its oldest minor" do
      expect(support_result(gem_with(requirement: "'>= 3.1'", matrix: %w[3 head])).status).to eq(:missing_evidence)
    end

    it "credits include: entries, but not exclude: entries, steps, or a lint job's pinned Ruby" do
      include_entry = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.3\"]\n        include:\n          - ruby: \"3.1\"\n"
      exclude_entry = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.3\"]\n        exclude:\n          - ruby: \"3.1\"\n"
      lint_pin = "jobs:\n  test:\n    strategy:\n      matrix:\n        ruby: [\"3.3\", \"3.4\"]\n  lint:\n    steps:\n      - uses: ruby/setup-ruby@v1\n        with:\n          ruby-version: \"3.1\"\n"
      steps = "jobs:\n  t:\n    steps:\n      - uses: ruby/setup-ruby@v1\n        with:\n          ruby-version:\n      - run: bundle exec rake\n"

      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: include_entry))).to be_verified
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: exclude_entry)).status).to eq(:missing_evidence)
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: lint_pin)).status).to eq(:missing_evidence)
      expect(Reanimator.discover(make_repo(files: gem_with(requirement: "'>= 3.1'", workflow: steps))).all(:ci_ruby_matrix)).to be_empty
    end

    it "keeps every matrix value as the workflow wrote it, and reads a whole YAML float as a bare major" do
      workflow = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [3.0, \"3.4\", truffleruby+graalvm, mingw, 3.4.0-preview1]\n"
      discovered = Reanimator.discover(make_repo(files: gem_with(requirement: "'>= 3.0'", workflow: workflow)))

      expect(discovered.value(:ci_ruby_matrix)).to eq(["3", "3.4", "truffleruby+graalvm", "mingw", "3.4.0-preview1"])
    end

    it "subtracts exclude: entries, alone or within a wider matrix" do
      bare = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n        exclude:\n          - ruby: \"3.1\"\n"
      with_os = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n        os: [ubuntu-latest, macos-latest]\n" \
        "        exclude:\n          - ruby: \"3.1\"\n            os: ubuntu-latest\n"
      everywhere = with_os + "          - ruby: \"3.1\"\n            os: macos-latest\n"

      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: bare)).status).to eq(:missing_evidence)
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: with_os))).to be_verified
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: everywhere)).status).to eq(:missing_evidence)
    end

    it "applies exclude: by value once the matrix is too large to enumerate" do
      many = (1..40).map { |i| "v#{i}" }.join(", ")
      workflow = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n        a: [#{many}]\n        b: [#{many}]\n" \
        "        exclude:\n          - ruby: \"3.1\"\n            a: v1\n"
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow)).status).to eq(:missing_evidence)
    end

    it "matches exclude values loosely on the by-value path too" do
      many = (1..40).map { |i| "v#{i}" }.join(", ")
      workflow = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.0\", \"3.4\"]\n        a: [#{many}]\n        b: [#{many}]\n" \
        "        exclude:\n          - ruby: 3.0\n            a: v1\n"
      expect(support_result(gem_with(requirement: "'>= 3.0'", workflow: workflow)).status).to eq(:missing_evidence)
    end

    it "reads only strings and numbers as Rubies, and refuses YAML aliases outright" do
      odd = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [{a: 1}, true, null, \"3.4\"]\n"
      bomb = "a: &a [\"x\", \"x\"]\nb: &b [*a, *a]\njobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [*b, \"3.1\"]\n"

      expect(Reanimator.discover(make_repo(files: gem_with(requirement: "'>= 3.4'", workflow: odd))).value(:ci_ruby_matrix)).to eq(["3.4"])
      expect(Reanimator.discover(make_repo(files: gem_with(requirement: "'>= 3.1'", workflow: bomb))).all(:ci_ruby_matrix)).to be_empty
    end

    it "does not read an expression as a Ruby" do
      workflow = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: ${{ fromJSON(needs.setup.outputs.rubies) }}\n" \
        "    steps:\n      - uses: ruby/setup-ruby@v1\n        with:\n          ruby-version: ${{ matrix.ruby }}\n"
      discovered = Reanimator.discover(make_repo(files: gem_with(requirement: "'>= 3.3'", workflow: workflow)))

      expect(discovered.all(:ci_ruby_matrix) + discovered.all(:ci_ruby_pinned)).to be_empty
    end

    it "never lets a single job's pinned Ruby stand in for a test matrix" do
      lone = "jobs:\n  lint:\n    steps:\n      - uses: ruby/setup-ruby@v1\n        with:\n          ruby-version: '2.7'\n"
      beside_expression = lone + "  test:\n    strategy:\n      matrix: ${{ fromJSON(needs.setup.outputs.matrix) }}\n"

      expect(support_result(gem_with(requirement: "'>= 2.7'", workflow: lone)).status).to eq(:missing_evidence)
      expect(support_result(gem_with(requirement: "'>= 2.7'", workflow: beside_expression)).status).to eq(:missing_evidence)
    end

    it "credits nothing from a matrix whose exclusions are only known at run time" do
      whole = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"2.7\", \"3.4\"]\n        exclude: ${{ fromJSON(vars.EXCLUDES) }}\n"
      entry = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"2.7\", \"3.4\"]\n        exclude:\n          - ruby: ${{ vars.OLD }}\n"

      [whole, entry].each do |workflow|
        expect(support_result(gem_with(requirement: "'>= 2.7'", workflow: workflow)).status).to eq(:missing_evidence)
      end
    end

    it "reads workflows with dates and symbols, as the contract file does" do
      workflow = "env:\n  SINCE: 2024-01-01\n  MODE: :fast\njobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n"
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow))).to be_verified
    end

    it "names a workflow it cannot read, without letting it soften the verdict" do
      aliased = "m: &m\n  ruby: [\"3.1\"]\njobs:\n  t:\n    strategy:\n      matrix:\n        <<: *m\n"
      invalid = "jobs: [unclosed\n"

      [aliased, invalid].each do |workflow|
        result = support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow))
        expect(result.status).to eq(:missing_evidence)
        expect(result.detail).to include("Not counted: .github/workflows/ci.yml could not be read")
      end
    end

    it "keeps a narrowing the readable workflows prove blocking when another workflow cannot be read" do
      files = blocking_support.merge(".github/workflows/release.yml" => "m: &m {}\njobs:\n  r:\n    <<: *m\n")
      baseline = Reanimator.baseline(make_repo(files: files))

      expect(baseline.result_for(:support_matrix).status).to eq(:missing_evidence)
      expect(baseline).to be_needs_attention
    end

    it "treats exclusions as unknowable when any matrix value is an expression" do
      other_dimension = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n        os: ${{ fromJSON(vars.OSES) }}\n" \
        "        exclude:\n          - ruby: \"3.1\"\n            os: ubuntu-latest\n"
      nested = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n        cfg: [{name: a}]\n" \
        "        exclude:\n          - ruby: \"3.1\"\n            cfg: {name: \"${{ vars.CFG }}\"}\n"

      [other_dimension, nested].each do |workflow|
        expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow)).status).to eq(:missing_evidence)
      end
    end

    it "matches exclude keys without regard to case" do
      workflow = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n        exclude:\n          - Ruby: \"3.1\"\n"
      expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow)).status).to eq(:missing_evidence)
    end

    it "takes the lowest floor across every mention, so a stray one cannot hide a narrowing" do
      real = "  s.required_ruby_version = \">= 3.1\"\n"
      shapes = {
        "=begin block" => "=begin\n  s.required_ruby_version = \">= 3.4\"\n=end\n#{real}",
        "earlier trailing comment" => "  s.name = \"w\" # next: required_ruby_version \">= 3.4\"\n#{real}",
        "description" => "  s.description = \"Needs required_ruby_version >= \\\"3.4\\\" soon\"\n#{real}"
      }
      shapes.each do |shape, lines|
        gemspec = "Gem::Specification.new do |s|\n#{lines}end\n"
        files = gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge("widget.gemspec" => gemspec)
        expect(support_result(files).status).to eq(:missing_evidence), shape
      end
    end

    it "matches exclude values loosely - case aside, and 7.0 as 7" do
      by_case = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n        os: [ubuntu-latest]\n" \
        "        exclude:\n          - ruby: \"3.1\"\n            os: Ubuntu-Latest\n"
      by_number = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n        rails: [7.0]\n" \
        "        exclude:\n          - ruby: \"3.1\"\n            rails: 7\n"

      [by_case, by_number].each do |workflow|
        expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow)).status).to eq(:missing_evidence)
      end
    end

    it "does not credit a job switched off with if: false, in any spelling" do
      ["false", "\"false\"", "${{ false }}", "${{false}}"].each do |condition|
        workflow = "jobs:\n  test:\n    strategy:\n      matrix:\n        ruby: [\"3.4\"]\n" \
          "  legacy:\n    if: #{condition}\n    strategy:\n      matrix:\n        ruby: [\"3.1\"]\n"
        expect(support_result(gem_with(requirement: "'>= 3.1'", workflow: workflow)).status).to eq(:missing_evidence), condition
      end
    end

    it "matches an exclude value that is a number against a string, and the reverse" do
      workflow = "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.0\", \"3.4\"]\n        os: [ubuntu-latest]\n" \
        "        exclude:\n          - ruby: 3.0\n            os: ubuntu-latest\n"
      expect(support_result(gem_with(requirement: "'>= 3.0'", workflow: workflow)).status).to eq(:missing_evidence)
    end

    it "treats a floor inside a =begin block as unreadable, since a heredoc can make it code" do
      gemspec = "Gem::Specification.new do |s|\n=begin\n  s.required_ruby_version = \">= 2.7\"\n=end\n  s.required_ruby_version = \">= 3.1\"\nend\n"
      files = gem_with(requirement: "'>= 3.1'", matrix: %w[3.1 3.4]).merge("widget.gemspec" => gemspec)
      expect(support_result(files).status).to eq(:missing_evidence)
    end

    it "ignores a commented-out lower floor" do
      gemspec = "Gem::Specification.new do |s|\n  # s.required_ruby_version = \">= 2.7\"\n  s.required_ruby_version = \">= 3.1\"\nend\n"
      files = gem_with(requirement: "'>= 3.1'", matrix: %w[3.1 3.4]).merge("widget.gemspec" => gemspec)
      expect(support_result(files)).to be_verified
    end

    it "does not read the floor from a commented-out line" do
      gemspec = "Gem::Specification.new do |s|\n  # required_ruby_version was bumped from \"3.3\"\n  s.required_ruby_version = \">= 3.1\"\nend\n"
      expect(support_result(narrowed_support.merge("widget.gemspec" => gemspec)).status).to eq(:missing_evidence)
    end

    it "takes no matrix from a workflow that does not parse" do
      broken = "jobs:\n  t:\n    strategy: [unclosed\n      matrix:\n        ruby: [\"3.1\"]\n"
      expect(Reanimator.discover(make_repo(files: gem_with(requirement: "'>= 3.1'", workflow: broken))).all(:ci_ruby_matrix)).to be_empty
    end

    it "ignores a trailing comment and reads an array spread over lines" do
      commented = "Gem::Specification.new { |s| s.required_ruby_version = '>= 3.3' # we dropped \"3.1\"\n}\n"
      multiline = "Gem::Specification.new do |s|\n  s.required_ruby_version = [\n    \">= 3.1\",\n    \"< 4\"\n  ]\nend\n"

      expect(support_result(narrowed_support.merge("widget.gemspec" => commented))).to be_verified
      expect(support_result(narrowed_support.merge("widget.gemspec" => multiline)).status).to eq(:missing_evidence)
    end

    it "reports a floor it cannot read as missing evidence, never as no floor" do
      {
        "constant" => "  s.required_ruby_version = MIN_RUBY\n",
        "%q()" => "  s.required_ruby_version = %q(>= 3.1)\n",
        "interpolation" => "  s.required_ruby_version = \">= \#{MIN}\"\n",
        "lookup" => "  s.required_ruby_version = gemspec['required_ruby_version']\n",
        "heredoc" => "  s.required_ruby_version = <<~R.strip\n    >= 3.1\n  R\n"
      }.each do |shape, line|
        gemspec = "Gem::Specification.new do |s|\n  # floor is 3.4 'soon'\n#{line}end\n"
        result = support_result(narrowed_support.merge("widget.gemspec" => gemspec))
        expect(result.status).to eq(:missing_evidence), shape
        expect(result.detail).to include("Write the floor as a string literal"), shape
        expect(Reanimator.discover(make_repo(files: narrowed_support.merge("widget.gemspec" => gemspec))).value(:supported_ruby))
          .to be_nil, shape
      end
    end

    it "treats any mention it cannot read as a literal assignment as an unreadable floor" do
      {
        "value on the next line" => "  s.required_ruby_version =\n    \">= 3.1\"\n",
        "requirement over lines" => "  s.required_ruby_version = Gem::Requirement.new(\n    \">= 3.1\"\n  )\n",
        "send" => "  s.send(:required_ruby_version=, \">= 3.1\")\n",
        "instance variable" => "  @spec.required_ruby_version = \">= 3.1\"\n",
        "or-assign" => "  s.required_ruby_version ||= \">= 3.1\"\n",
        "leading-dot chain" => "  s\n    .required_ruby_version = \">= 3.1\"\n",
        "comparison" => "  raise unless s.required_ruby_version == \">= 3.4\"\n  s.required_ruby_version = \">= 3.1\"\n",
        "description" => "  s.description = \"needs required_ruby_version 3.4\"\n  s.required_ruby_version = \">= 3.1\"\n"
      }.each do |shape, lines|
        gemspec = "Gem::Specification.new do |s|\n#{lines}end\n"
        files = gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge("widget.gemspec" => gemspec)
        result = support_result(files)
        expect(result.status).to eq(:missing_evidence), shape
        expect(result.detail).to include("Write the floor as a string literal"), shape
      end
    end

    it "fails closed on code hidden where a line-by-line reader cannot follow it" do
      {
        "interpolation in a heredoc" => "  s.description = <<~D\n    \#{s.required_ruby_version = \">= 2.7\"; nil}\n  D\n",
        "=begin inside a heredoc" => "  s.description = <<-D\n=begin\n  D\n  s.required_ruby_version = \">= 2.7\"\n",
        "__END__ inside a heredoc" => "  s.description = <<~D\n__END__\n  D\n  s.required_ruby_version = \">= 2.7\"\n",
        "=begin and =end in two heredocs" => "  s.summary = <<-D\n=begin\n  D\n  s.required_ruby_version = \">= 2.7\"\n  s.description = <<-D\n=end\n  D\n",
        "trailing comma" => "  s.required_ruby_version = \">= 3.3\",\n    \">= 2.7\"\n",
        "next-line method chain" => "  s.required_ruby_version = \">= 3.3\"\n    .sub(\"3.3\", \"2.7\")\n",
        "next-line safe navigation" => "  s.required_ruby_version = \">= 3.3\"\n    &.sub(\"3.3\", \"2.7\")\n",
        "next-line &&" => "  s.required_ruby_version = \">= 3.3\"\n    && \">= 2.7\"\n",
        "next-line ||" => "  s.required_ruby_version = \">= 3.3\"\n    || \">= 2.7\"\n",
        "next-line and" => "  s.required_ruby_version = \">= 3.3\"\n    and \">= 2.7\"\n",
        "next-line or" => "  s.required_ruby_version = \">= 3.3\"\n    or \">= 2.7\"\n"
      }.each do |shape, lines|
        gemspec = "Gem::Specification.new do |s|\n#{lines}end\n"
        files = gem_with(requirement: "'>= 3.1'", matrix: %w[3.3]).merge("widget.gemspec" => gemspec)
        expect(support_result(files).status).to eq(:missing_evidence), shape
      end
    end

    describe "a floor set in a file the gemspec loads" do
      def floor_in(files) = Reanimator.discover(make_repo(files: gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(files)))

      def gemspec_loading(load) = {"widget.gemspec" => "#{load}\nGem::Specification.new { |s| common_spec(s) }\n"}

      let(:common) { "def common_spec(s)\n  s.required_ruby_version = '>= 3.2'\nend\n" }

      it "is read through each way a gemspec names a local file" do
        {
          "require_relative" => ["require_relative './gemspec'", "gemspec.rb"],
          "load" => ["load 'gemspec.rb'", "gemspec.rb"],
          "require from lib" => ["require 'widget/gemspec'", "lib/widget/gemspec.rb"],
          "expand_path from __dir__" => ["require File.expand_path('gemspec', __dir__)", "gemspec.rb"],
          "expand_path from __FILE__" => ["require File.expand_path('../lib/common', __FILE__)", "lib/common.rb"],
          "dirname joined" => ["require File.dirname(__FILE__) + '/lib/common'", "lib/common.rb"],
          "require from the root" => ["require './gemspec'", "gemspec.rb"],
          "a file named with ~" => ["require_relative '~common'", "~common.rb"]
        }.each do |shape, (load, path)|
          expect(floor_in(gemspec_loading(load).merge(path => common)).value(:supported_ruby)).to eq([">= 3.2"]), shape
        end
      end

      it "follows nested loads relative to the file that loads them" do
        files = gemspec_loading("require_relative 'lib/widget/spec_helper'").merge(
          "lib/widget/spec_helper.rb" => "require_relative 'common'\n",
          "lib/widget/common.rb" => common
        )
        expect(floor_in(files).value(:supported_ruby)).to eq([">= 3.2"])
        expect(support_result(gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(files)).status).to eq(:missing_evidence)
      end

      it "reads each file whole, so __END__ in one does not hide the next" do
        files = {
          "widget.gemspec" => "require_relative 'lib/widget/version'\nrequire_relative 'gemspec'\nGem::Specification.new { |s| common_spec(s) }\n__END__\nnotes\n",
          "lib/widget/version.rb" => "module Widget; VERSION = '1'; end\n__END__\nnotes\n",
          "gemspec.rb" => common
        }
        expect(floor_in(files).value(:supported_ruby)).to eq([">= 3.2"])
      end

      it "reads files as UTF-8 whatever the locale" do
        files = {
          "widget.gemspec" => "require_relative 'lib/widget/version'\nGem::Specification.new { |s| s.authors = ['J\u00F6rg']; s.required_ruby_version = '>= 2.7' }\n",
          "lib/widget/version.rb" => "# Copyright \u00A9 2024\nmodule Widget; VERSION = '1'; end\n"
        }
        external = Encoding.default_external
        Encoding.default_external = Encoding::US_ASCII
        expect(floor_in(files).value(:supported_ruby)).to eq([">= 2.7"])
      ensure
        Encoding.default_external = external
      end

      it "treats a load it cannot follow as an unreadable floor when no floor was found" do
        outside = Dir.mktmpdir("reanimator-outside")
        File.write(File.join(outside, "shared.rb"), common)
        repo = make_repo(files: gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(gemspec_loading("require_relative 'shared'")))
        File.symlink(File.join(outside, "shared.rb"), File.join(repo, "shared.rb"))
        expect(Reanimator.discover(repo).value(:supported_ruby_unreadable)).to include("require_relative 'shared'")

        {
          "outside the repository" => "require_relative '../shared'",
          "an absolute path" => "require_relative '#{File.realpath(outside)}/shared'",
          "a missing file" => "require_relative 'nowhere'",
          "a built path" => "require File.join(__dir__, 'gemspec')",
          "a suffix added" => "require_relative 'gemspec' + '_low'",
          "an adjacent literal" => "require_relative 'gemspec' '_low'",
          "a joined path with a suffix" => "require File.dirname(__FILE__) + '/gemspec' + '_low'",
          "a joined path without a slash" => "require __dir__ + 'gemspec'",
          "load of ~" => "load '~gemspec.rb'",
          "require of ~" => "require '~gemspec'",
          "expand_path of ~" => "require File.expand_path('~/gemspec', __dir__)"
        }.each do |shape, load|
          discovered = floor_in(gemspec_loading(load).merge("gemspec.rb" => common, "~gemspec.rb" => common, "~/gemspec.rb" => common, "lib/~gemspec.rb" => common))
          expect(discovered.value(:supported_ruby_unreadable)).to include(load), shape
          expect(discovered.value(:supported_ruby)).to be_nil, shape
        end
      ensure
        FileUtils.rm_rf(outside)
      end

      it "does not follow loads through a symlink, which Ruby resolves from where the link sits" do
        repo = make_repo(files: gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(
          gemspec_loading("require_relative 'lib/linked'"), "other/common.rb" => common, "lib/widget.rb" => ""
        ))
        File.symlink(File.join(repo, "other/common.rb"), File.join(repo, "lib/linked.rb"))
        expect(Reanimator.discover(repo).value(:supported_ruby_unreadable)).to include("require_relative 'lib/linked'")

        linked = make_repo(files: gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(
          "sub/real.gemspec" => "require_relative 'common'\nGem::Specification.new { |s| common_spec(s) }\n", "sub/common.rb" => common
        ).except("widget.gemspec"))
        File.symlink(File.join(linked, "sub/real.gemspec"), File.join(linked, "widget.gemspec"))
        expect(Reanimator.discover(linked).value(:supported_ruby_unreadable)).to include("it is a symlink")
      end

      it "treats a loaded file it cannot read as an unreadable floor" do
        skip "root reads anything" if Process.uid.zero?
        repo = make_repo(files: gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(gemspec_loading("require_relative 'gemspec'"), "gemspec.rb" => common))
        File.chmod(0o000, File.join(repo, "gemspec.rb"))
        expect(Reanimator.discover(repo).value(:supported_ruby_unreadable)).to eq("gemspec.rb could not be read")
      ensure
        File.chmod(0o644, File.join(repo, "gemspec.rb")) if repo
      end

      it "follows four levels of loads, a cycle once, and neither a commented-out load nor a load with .rb added" do
        chain = (1..5).to_h { |n| ["level#{n}.rb", (n == 5) ? common : "require_relative 'level#{n + 1}'\n"] }
        expect(floor_in(gemspec_loading("require_relative 'level1'").merge(chain.except("level5.rb"), "level4.rb" => common))
          .value(:supported_ruby)).to eq([">= 3.2"])
        expect(floor_in(gemspec_loading("require_relative 'level1'").merge(chain)).value(:supported_ruby_unreadable))
          .to eq("it loads files more than 4 levels deep")

        cycle = gemspec_loading("require_relative 'a'").merge("a.rb" => "require_relative 'b'\n", "b.rb" => "require_relative 'a'\n")
        commented = gemspec_loading("# was: require 'x'; require_relative 'nowhere'")
        exact = gemspec_loading("load 'gemspec.common'").merge("gemspec.common" => common)
        expect([cycle, commented].map { |files| floor_in(files).value(:supported_ruby_unreadable) }).to eq([nil, nil])
        expect(floor_in(exact).value(:supported_ruby)).to eq([">= 3.2"])
      end

      it "settles an unfollowed load only with a floor in the gemspec itself" do
        files = gemspec_loading("require_relative 'gemspec'\nrequire File.join(__dir__, 'platform')").merge("gemspec.rb" => common)
        expect(floor_in(files).value(:supported_ruby_unreadable)).to include("File.join(__dir__, 'platform')")
      end

      it "treats a path Ruby could not use as unfollowed, never as a crash" do
        allow(Reanimator.logger).to receive(:warn)
        {"home directory" => "load '~nosuchuser/x.rb' if false", "null byte" => "require_relative \"a\u0000b\" if false"}.each do |shape, load|
          files = {"widget.gemspec" => "#{load}\nGem::Specification.new { |s| s.required_ruby_version = '>= 3.1' }\n"}
          expect(floor_in(files).value(:supported_ruby)).to eq([">= 3.1"]), shape
        end
        expect(Reanimator.logger).not_to have_received(:warn)
      end

      it "reads a loaded file with invalid bytes, and never opens a FIFO it names" do
        invalid = gemspec_loading("require_relative 'gemspec'").merge("gemspec.rb" => "MARK = \"\xFF\"\n#{common}".b)
        expect(floor_in(invalid).value(:supported_ruby)).to eq([">= 3.2"])

        repo = make_repo(files: gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(gemspec_loading("load 'pipe'")))
        File.mkfifo(File.join(repo, "pipe"))
        discovered = Timeout.timeout(5) { Reanimator.discover(repo) }
        expect(discovered.value(:supported_ruby_unreadable)).to include("load 'pipe'")
      end

      it "treats a floor after a =begin never closed as unreadable" do
        files = {"widget.gemspec" => "Gem::Specification.new do |s|\n=begin\n  s.required_ruby_version = '>= 2.7'\nend\n"}
        expect(floor_in(files).value(:supported_ruby_unreadable)).to include("sits after __END__ or inside =begin")
      end

      it "keeps a literal floor in the gemspec when another load cannot be followed" do
        files = {"widget.gemspec" => "require 'bundler'\nrequire File.join(__dir__, 'x')\nGem::Specification.new { |s| s.required_ruby_version = '>= 3.1' }\n"}
        expect(floor_in(files).value(:supported_ruby)).to eq([">= 3.1"])
      end
    end

    it "reads nothing after __END__ but fails closed on a floor mentioned there, and reads a Gem::Requirement.new floor" do
      floor = "Gem::Specification.new do |s|\n  s.required_ruby_version = Gem::Requirement.new(\">= 3.1\")\nend\n__END__\n"
      discovered = Reanimator.discover(make_repo(files: narrowed_support.merge("widget.gemspec" => "#{floor}notes\n")))
      expect(discovered.value(:supported_ruby)).to eq([">= 3.1"])
      expect(discovered.value(:supported_ruby_unreadable)).to be_nil

      mentioned = narrowed_support.merge("widget.gemspec" => "#{floor}required_ruby_version notes\n")
      expect(Reanimator.discover(make_repo(files: mentioned)).value(:supported_ruby_unreadable)).not_to be_nil
    end

    it "reads a frozen literal, and a # inside a string is not a comment" do
      gemspec = "Gem::Specification.new do |s|\n  s.required_ruby_version = [\">= 3.1\".freeze, \"!= 3.2.#0\"] # was 2.7\nend\n"
      discovered = Reanimator.discover(make_repo(files: narrowed_support.merge("widget.gemspec" => gemspec)))
      expect(discovered.value(:supported_ruby)).to eq([">= 3.1", "!= 3.2.#0"])
    end

    it "reads every gemspec, so a second one can neither hide nor raise the floor" do
      floorless = "Gem::Specification.new { |s| s.name = \"w-cloud\" }\n"
      higher = "Gem::Specification.new { |s| s.required_ruby_version = \">= 3.4\" }\n"
      base = gem_with(requirement: "'>= 3.1'", matrix: %w[3.4])

      expect(support_result(base.merge("a-cloud.gemspec" => floorless)).status).to eq(:missing_evidence)
      expect(support_result(base.merge("a-pro.gemspec" => higher)).status).to eq(:missing_evidence)
    end

    it "reports a requirement that does not parse rather than dropping it" do
      result = support_result(gem_with(requirement: "'>= three'"))
      expect(result.status).to eq(:missing_evidence)
      expect(result.detail).to include("could not be parsed as a requirement")
    end

    it "reads a multi-line array even after another array on the same line" do
      gemspec = "Gem::Specification.new do |s|\n  s.files = [\"lib/w.rb\"]; s.required_ruby_version = [\n    \">= 3.1\",\n    \"< 4\"\n  ]\nend\n"
      expect(support_result(narrowed_support.merge("widget.gemspec" => gemspec)).status).to eq(:missing_evidence)
      expect(Reanimator.discover(make_repo(files: narrowed_support.merge("widget.gemspec" => gemspec))).value(:supported_ruby))
        .to eq([">= 3.1", "< 4"])
    end

    it "records every workflow's matrix in the drift snapshot, as the evaluator reads them" do
      files = gem_with(requirement: "'>= 3.1'", matrix: %w[3.4]).merge(
        ".github/workflows/test.yml" => "jobs:\n  t:\n    strategy:\n      matrix:\n        ruby: [\"3.1\", \"3.4\"]\n"
      )
      expect(Reanimator.snapshot(make_repo(files: files)).support_matrix).to contain_exactly("3.1", "3.4")
    end

    [Reanimator::Detectors::Bundler, Reanimator::Detectors::GitHubActions].each do |detector|
      it "treats a crashed #{detector.name.split("::").last} detector as missing evidence, never as nothing declared" do
        crash(detector, Encoding::CompatibilityError.new("boom"))
        result = support_result(narrowed_support)
        expect(result.status).to eq(:missing_evidence)
        expect(result.detail).to include("the #{detector.name.split("::").last} detector failed (Encoding::CompatibilityError: boom)")
      end
    end

    it "treats >= 0 as no floor at all" do
      expect(support_result(gem_with(requirement: "'>= 0'"))).to be_verified
    end

    it "treats a matrix of no released Ruby as missing evidence" do
      result = support_result(gem_with(requirement: "'>= 3.1'", matrix: %w[head jruby truffleruby]))

      expect(result.status).to eq(:missing_evidence)
      expect(result.detail).to include("CI pins no specific released Ruby")
    end
  end

  describe Reanimator::Baseline do
    def baseline_with(statuses, required:, executed: false, requested: executed)
      results = statuses.each_with_index.map do |status, i|
        criterion = Reanimator::AcceptanceCriterion.new(id: :"c#{i}", claim: "c#{i}", evaluator: :command, required: required)
        Reanimator::CriterionResult.new(criterion: criterion, status: status)
      end
      contract = Reanimator.contract(make_repo(files: {"README.md" => "x"}))
      Reanimator::Baseline.new(contract: contract, results: results, state: Reanimator::RepositoryState.fetch(:unproven),
        generated_at: Time.now, executed: executed, execution_requested: requested)
    end

    it "escalates required problems, but not checks that were planned or beyond Reanimator" do
      baseline = baseline_with(%i[failed missing_evidence skipped error planned unavailable verified], required: true)

      expect(baseline.escalations.map(&:status)).to eq(%i[failed missing_evidence skipped error])
    end

    it "escalates a required criterion nobody can evaluate - a typo is something to fix" do
      typo = Reanimator.baseline(make_repo(files: blocking_support.merge(".reanimator.yml" =>
        blocking_support[".reanimator.yml"].sub("evaluator: support_matrix", "evaluator: suport_matrix"))))
      undeclared = Reanimator.baseline(make_repo(files: {"README.md" => "x", ".reanimator.yml" => blocking_support[".reanimator.yml"]}))

      expect(typo.result_for(:support_matrix).status).to eq(:skipped)
      expect(typo).to be_needs_attention
      expect(undeclared).to be_needs_attention
    end

    it "does not hold every Rails app at exit 2 for a boot smoke Reanimator cannot run" do
      rails = Reanimator.baseline(make_repo(files: {
        "Gemfile" => "gem 'rails'\n", "config/application.rb" => "class App < Rails::Application; end\n",
        ".reanimator.yml" => "version: 1\nintent: maintain\nprofile: rails-app\n"
      }))

      expect(rails.result_for(:boot).status).to eq(:unavailable)
      expect(rails.state.to_sym).to eq(:unproven)
      expect(rails.escalations.map { |r| r.criterion.id }).not_to include(:boot)
    end

    it "escalates planned and unavailable checks when execution was asked for and withheld" do
      expect(baseline_with(%i[planned unavailable], required: true, requested: true).escalations.size).to eq(2)
    end

    it "notes advisory problems without letting them block" do
      baseline = baseline_with(%i[failed missing_evidence error skipped planned unavailable verified], required: false)

      expect(baseline.advisories.map(&:status)).to eq(%i[failed missing_evidence error])
      expect(baseline).not_to be_needs_attention
      expect(baseline.findings.map(&:level).uniq).to eq([:notice])
    end
  end

  describe Reanimator::Run do
    it "needs a human for everything but a healthy no-op" do
      repository = Reanimator::Repository.at(make_repo(files: {"README.md" => "x"}))
      needs = Reanimator::Run::OUTCOMES.to_h do |outcome|
        [outcome, Reanimator::Run.new(outcome: outcome, repository: repository, policy_version: "g@1", trigger: "t").needs_attention?]
      end

      expect(needs).to eq(no_op: false, report: true, draft_pr: true, escalation: true, safe_stop: true)
    end
  end

  describe Reanimator::Finding do
    it "refuses a level GitHub would not understand" do
      expect { Reanimator::Finding.new(:warn, "t", "m") }.to raise_error(Reanimator::UnknownError, /:warn/)
    end

    it "gives a waiting draft a message even without a reason" do
      repository = Reanimator::Repository.at(make_repo(files: {"README.md" => "x"}))
      run = Reanimator::Run.new(outcome: :draft_pr, repository: repository, policy_version: "g@1", trigger: "t")

      expect(run.findings.map(&:message)).to eq([Reanimator::Run::DRAFT_WAITING])
    end
  end

  describe Reanimator::Reports::Annotations do
    it "renders blocking findings as errors and advisory ones as notices, escaped" do
      lines = described_class.new([
        Reanimator::Finding.new(:error, "acme/widget tests", "100% broken,\nreally\r::stop"),
        Reanimator::Finding.new(:notice, "acme/widget lint: style, again", "advisory")
      ]).render

      expect(lines).to eq([
        "::error title=Reanimator%3A acme/widget tests::100%25 broken,%0Areally%0D::stop",
        "::notice title=Reanimator%3A acme/widget lint%3A style%2C again::advisory"
      ])
    end

    it "carries a baseline's blocking criterion as one error" do
      lines = described_class.new(Reanimator.baseline(make_repo(files: blocking_support)).findings).render

      expect(lines.grep(/support_matrix::/)).to contain_exactly(a_string_starting_with("::error ").and(including("CI's lowest Ruby is 3.3")))
    end
  end

  describe Reanimator::ActionsSurface do
    let(:env) { {"GITHUB_ACTIONS" => "true", "GITHUB_STEP_SUMMARY" => File.join(make_repo(files: {}), "summary.md")} }

    it "prints reports between stop-commands markers so their text cannot act as a command" do
      out = StringIO.new
      described_class.print_report("claim\n::error::forged", env: env, out: out)
      lines = out.string.lines.map(&:chomp)

      expect(lines.first).to match(/\A::stop-commands::\h{32}\z/)
      expect(lines.last).to eq("::#{lines.first.split("::").last}::")
      expect(lines[1..-2]).to eq(["claim", "::error::forged"])
    end

    it "appends to the job summary, fenced longer than any backticks in it" do
      2.times { |i| described_class.publish(annotations: [], summaries: [["run #{i}", "``` not a fence"]], env: env, out: StringIO.new) }
      summary = File.read(env["GITHUB_STEP_SUMMARY"])

      expect(summary).to include("### run 0", "### run 1", "````\n``` not a fence\n````")
    end

    it "keeps a heading on one line" do
      described_class.publish(annotations: [], summaries: [["repo\n::error::x", "body"]], env: env, out: StringIO.new)
      expect(File.read(env["GITHUB_STEP_SUMMARY"])).to start_with("### repo ::error::x\n")
    end

    it "reports an unwritable summary instead of raising" do
      err = StringIO.new
      described_class.publish(annotations: [], summaries: [["x", "y"]],
        env: env.merge("GITHUB_STEP_SUMMARY" => "/nonexistent/dir/summary.md"), out: StringIO.new, err: err)

      expect(err.string).to include("could not write the job summary")
    end
  end

  describe "the CLI" do
    # Clears the Actions variables unless an example sets them, so a run of
    # this suite inside Actions never writes fixtures into the real summary.
    def run_cli(*args, env: {})
      out = StringIO.new
      err = StringIO.new
      status = 0
      previous = [$stdout, $stderr]
      stub_const("ENV", ENV.to_h.merge("GITHUB_ACTIONS" => nil, "GITHUB_STEP_SUMMARY" => nil).merge(env))
      $stdout = out
      $stderr = err
      begin
        Reanimator::CLI.start(args)
      rescue SystemExit => e
        status = e.status
      ensure
        $stdout, $stderr = previous
      end
      [status, out.string, err.string]
    end

    it "blocks a baseline whose discovery was incomplete, though inference then asks for less" do
      failing_gem = {"widget.gemspec" => "Gem::Specification.new { |s| s.name = 'widget' }\n", "README.md" => "# widget"}
      crash(Reanimator::Detectors::RubyGem)
      baseline = Reanimator.baseline(make_repo(files: failing_gem))

      expect(baseline.contract.profile.id).not_to eq(:"ruby-gem")
      expect(baseline.state.alive?).to be(false)
      expect(baseline.escalations.map { |result| result.criterion.id }).to include(:discovery_complete)
      expect(baseline.result_for(:discovery_complete).detail).to include("the RubyGem detector failed (ArgumentError: boom)")
      expect(run_cli("baseline", make_repo(files: failing_gem)).first).to eq(2)
    end

    it "never lets a waiver or a declared check stand in for discovery_complete" do
      contract = <<~YAML
        version: 1
        profile: generic
        waivers:
          - target: discovery_complete
            reason: "a waiver cannot cover a crash"
            expires: 2999-01-01
      YAML
      crash(Reanimator::Detectors::Fork)
      baseline = Reanimator.baseline(make_repo(files: {".reanimator.yml" => contract}))
      expect(baseline.result_for(:discovery_complete).status).to eq(:error)
      expect(baseline.state.alive?).to be(false)

      declared = "version: 1\nacceptance:\n  checks:\n    - id: discovery_complete\n      run: \"true\"\n"
      expect { Reanimator.contract(make_repo(files: {".reanimator.yml" => declared})) }
        .to raise_error(Reanimator::ContractError, /reserved/)
    end

    it "refuses to export a contract read in part" do
      repo = make_repo(files: narrowed_support)
      crash(Reanimator::Detectors::RubyGem)
      status, out, err = run_cli("contract", repo, "--export")
      expect([status, out, err]).to match([1, "", /cannot be exported/])
      expect { Reanimator.contract(repo).to_minimal_hash }.to raise_error(Reanimator::DiscoveryIncomplete)
      expect(run_cli("contract", repo)[1]).to include("Read in part: the RubyGem detector failed")
    end

    it "refuses to record or compare a contract read in part" do
      repo = make_repo(files: narrowed_support)
      crash(Reanimator::Detectors::GitHubActions)

      expect { Reanimator.snapshot(repo) }.to raise_error(Reanimator::DiscoveryIncomplete, /GitHubActions detector failed/)
      status, _out, err = run_cli("drift", repo, "--record")
      expect([status, err]).to match([1, /read in part/])
      expect(File.exist?(File.join(repo, ".reanimator-snapshot.json"))).to be(false)
      expect(Reanimator.portfolio_drift([repo, make_repo(files: narrowed_support)]).requires_review?).to be(true)
    end

    let(:actions) { {"GITHUB_ACTIONS" => "true", "GITHUB_STEP_SUMMARY" => File.join(make_repo(files: {}), "summary.md")} }

    it "exits 2, annotates a blocking finding once, and writes the check to the job summary" do
      status, output = run_cli("baseline", make_repo(files: blocking_support), env: actions)

      expect(status).to eq(2)
      expect(output.lines.grep(/\A::error .*support_matrix::/).size).to eq(1)
      expect(File.read(actions["GITHUB_STEP_SUMMARY"])).to include("### Reanimator", "REANIMATOR / VITALITY", "Attention needed")
    end

    it "notes advisory problems without failing the job" do
      status, output = run_cli("baseline", make_repo(files: narrowed_support), env: actions)

      expect(status).to eq(0)
      expect(output.lines.grep(/\A::notice .*support_matrix::/).size).to eq(1)
      expect(output).not_to match(/^::(error|warning) /)
    end

    it "keeps --format json valid inside Actions" do
      status, output = run_cli("baseline", make_repo(files: blocking_support), "--format", "json", env: actions)

      expect(status).to eq(2)
      expect(JSON.parse(output)).to include("state" => "unproven")
    end

    it "publishes nothing outside Actions but still exits 2" do
      status, output = run_cli("baseline", make_repo(files: blocking_support), env: {"GITHUB_ACTIONS" => nil})

      expect(status).to eq(2)
      expect(output).not_to include("::")
    end

    it "keeps repository text from silencing the real annotations" do
      claim = "Owned.\n::stop-commands::tok\n::error::forged"
      files = blocking_support.merge(".reanimator.yml" => blocking_support[".reanimator.yml"].sub(
        'claim: "Declared Ruby versions are exercised."', "claim: #{claim.inspect}"
      ))
      _status, output = run_cli("baseline", make_repo(files: files), env: actions)
      lines = output.lines.map(&:chomp)
      opened = lines.index { |l| l.match?(/\A::stop-commands::\h{32}\z/) }
      closed = lines.index("::#{lines[opened].split("::").last}::")

      expect(lines.index("::stop-commands::tok")).to be_between(opened, closed)
      expect(lines[(closed + 1)..].grep(/\A::error .*support_matrix::/).size).to eq(1)
    end

    it "guards every command that prints repository text, and its errors" do
      contract = "version: 1\nintent: maintain\nprofile: generic\nacceptance:\n  checks:\n    - id: x\n      run: \"echo\\n::error::forged\"\n"
      root = make_repo(files: {".reanimator.yml" => contract, ".reanimator-snapshot.json" => "{\n::error::from-snapshot"})

      _status, output = run_cli("contract", root, env: actions)
      lines = output.lines.map(&:chomp)
      opened = lines.index { |l| l.match?(/\A::stop-commands::\h{32}\z/) }
      closed = lines.index("::#{lines[opened].split("::").last}::")
      expect(lines.index("::error::forged")).to be_between(opened, closed)

      _status, output = run_cli("discover", root, env: actions)
      expect(output.lines.first).to match(/\A::stop-commands::\h{32}$/)
      _status, _output, errors = run_cli("drift", root, env: actions)
      expect(errors.lines.first).to match(/\A::stop-commands::\h{32}$/)
    end

    it "keeps a crafted workflow file name from becoming its own log line" do
      root = make_repo(files: gem_with(requirement: "'>= 3.3'"))
      FileUtils.mkdir_p(File.join(root, ".github/workflows", "x\n::error title=forged::forged\n.yml"))
      out, err, = Open3.capture3(QUIET_CI, RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
        File.expand_path("../../exe/reanimator", __dir__), "baseline", root, "--format", "json")

      expect((out + err).lines.grep(/\A::error/)).to be_empty
      expect(JSON.parse(out)["results"].map { |r| r["id"] }).to include("support_matrix")
    end

    it "does not let a directory named like a workflow knock out the real ones" do
      root = make_repo(files: gem_with(requirement: "'>= 3.3'"))
      FileUtils.mkdir_p(File.join(root, ".github/workflows/archive.yml"))

      expect(Reanimator.discover(root).value(:ci_ruby_matrix)).to eq(%w[3.3 3.4])
    end

    it "keeps every log entry on one line with the default logger" do
      script = 'Reanimator.logger.warn("first\n::error::forged\r\nlast")'
      _out, err, = Open3.capture3(QUIET_CI, RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-rreanimator", "-e", script)

      expect(err.lines.size).to eq(1)
      expect(err).to include("first ::error::forged last")
    end

    it "says plainly what a no-op leaves unproven" do
      root = make_repo(files: {".reanimator.yml" => <<~YAML})
        version: 1
        intent: maintain
        profile: generic
        autonomy:
          repair: allowed
        acceptance:
          checks:
            - id: suite
              run: "true"
              required: true
            - id: boot
              evaluator: http_smoke
              required: true
      YAML
      status, output = run_cli("repair", root)

      expect(status).to eq(0)
      expect(output).to include("Outcome:  NO-OP (nothing to repair)",
        "Nothing to repair. Still unproven, because Reanimator cannot establish the proof yet: boot.")
      expect(output).not_to include("healthy")
      expect(output).not_to include("All required criteria pass")
    end

    it "exits 2 when execution was asked for and withheld" do
      allow(Reanimator.configuration).to receive(:allow_execution).and_return(false)
      status, = run_cli("baseline", make_repo(files: gem_with(requirement: "'>= 3.3'")), "--execute")

      expect(status).to eq(2)
    end

    it "reports unreadable input before a member's escalation" do
      status, = run_cli("portfolio", make_repo(files: blocking_support), "/nonexistent/repo")
      expect(status).to eq(1)
    end

    it "guards every command that prints a report" do
      root = make_repo(files: gem_with(requirement: "'>= 3.3'"))
      [%w[inventory], %w[discover], %w[contract], %w[permissions], %w[families], %w[gates], %w[drift]].each do |(command)|
        _status, output = run_cli(command, root, env: actions)
        expect(output.lines.first).to match(/\A::stop-commands::\h{32}$/), command
      end
      _status, output = run_cli("agents", env: actions)
      expect(output.lines.first).to match(/\A::stop-commands::\h{32}$/)
    end

    it "keeps --format json parseable when a detector warns, with the default logger" do
      root = make_repo(files: gem_with(requirement: "'>= 3.3'"))
      crash = File.join(make_repo, "crash.rb")
      File.write(crash, "require 'reanimator'\nReanimator::Detectors::Commands.prepend(Module.new { def detect = raise('boom') })\n")
      exe = File.expand_path("../../exe/reanimator", __dir__)
      output, warnings, status = Open3.capture3(QUIET_CI, RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
        "-r", crash, exe, "baseline", root, "--format", "json")

      expect(warnings).to include("Commands")
      expect(JSON.parse(output)["results"].map { |result| result["id"] }).to include("discovery_complete")
      expect(status.exitstatus).to eq(2)
    end

    it "exits 1 when a portfolio path cannot be read, and 2 when a member needs a human" do
      bad, = run_cli("portfolio", make_repo(files: gem_with(requirement: "'>= 3.3'")), "/nonexistent/repo")
      blocking, = run_cli("portfolio", make_repo(files: gem_with(requirement: "'>= 3.3'")), make_repo(files: blocking_support))

      expect(bad).to eq(1)
      expect(blocking).to eq(2)
    end

    it "exits 2 when a repair escalates" do
      status, output = run_cli("repair", make_repo(files: {".reanimator.yml" => <<~YAML}))
        version: 1
        intent: maintain
        profile: generic
        acceptance:
          checks:
            - id: suite
              run: "false"
              required: true
      YAML

      expect(status).to eq(2)
      expect(output).to include("ESCALATION")
    end

    it "escalates rather than calling a repository healthy when nothing failed but something is unproven" do
      status, output = run_cli("repair", make_repo(files: blocking_support.merge(".reanimator.yml" => <<~YAML)))
        version: 1
        intent: maintain
        profile: generic
        autonomy:
          repair: allowed
        acceptance:
          checks:
            - id: support_matrix
              claim: "Declared Ruby versions are exercised."
              evaluator: support_matrix
              required: true
      YAML

      expect(status).to eq(2)
      expect(output).to include("ESCALATION", "Nothing failed to repair, but required criteria are unproven: support_matrix")
    end
  end
end
