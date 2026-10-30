# frozen_string_literal: true

require "open3"

# Section 16: an escalation has to reach a human without anyone reading a
# terminal. The CLI's exit status carries it everywhere; inside GitHub Actions
# it also becomes one annotation per finding and a job-summary entry - and
# nothing the repository writes can forge or silence either.
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

    it "takes nothing from a workflow that does not parse" do
      broken = "jobs:\n  t:\n    strategy: [unclosed\n      matrix:\n        ruby: [\"3.1\"]\n"
      expect(Reanimator.discover(make_repo(files: gem_with(requirement: "'>= 3.1'", workflow: broken))).all(:ci_ruby_matrix)).to be_empty
    end

    it "ignores a trailing comment and reads an array spread over lines" do
      commented = "Gem::Specification.new { |s| s.required_ruby_version = '>= 3.3' # we dropped \"3.1\"\n}\n"
      multiline = "Gem::Specification.new do |s|\n  s.required_ruby_version = [\n    \">= 3.1\",\n    \"< 4\"\n  ]\nend\n"

      expect(support_result(narrowed_support.merge("widget.gemspec" => commented))).to be_verified
      expect(support_result(narrowed_support.merge("widget.gemspec" => multiline)).status).to eq(:missing_evidence)
    end

    it "keeps an unquoted requirement as written" do
      files = narrowed_support.merge("widget.gemspec" => "Gem::Specification.new { |s| s.required_ruby_version = RUBY_FLOOR }\n")
      expect(Reanimator.discover(make_repo(files: files)).value(:supported_ruby)).to eq(["RUBY_FLOOR }"])
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
      output, warnings, = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), exe,
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
