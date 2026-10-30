# frozen_string_literal: true

require "open3"

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

    it "ignores a lower floor inside a =begin block" do
      gemspec = "Gem::Specification.new do |s|\n=begin\n  s.required_ruby_version = \">= 2.7\"\n=end\n  s.required_ruby_version = \">= 3.1\"\nend\n"
      files = gem_with(requirement: "'>= 3.1'", matrix: %w[3.1 3.4]).merge("widget.gemspec" => gemspec)
      expect(support_result(files)).to be_verified
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
      root = make_repo(files: gem_with(requirement: "'>= 3.3'").merge("package.json" => "[1]"))
      exe = File.expand_path("../../exe/reanimator", __dir__)
      output, warnings, = Open3.capture3(QUIET_CI, RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), exe,
        "baseline", root, "--format", "json")

      expect(warnings).to include("Commands")
      expect { JSON.parse(output) }.not_to raise_error
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
