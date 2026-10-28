# frozen_string_literal: true

BROKEN_LIB = "module Calc\n  module_function\n  def add(a, b)\n    a - b\n  end\nend\n"
CHECK = %(require "calc"\nraise "broken" unless Calc.add(2, 2) == 4\n)

RSpec.describe Reanimator::RepairRun do
  def broken_repo(repair: :disabled, submit: false)
    autonomy = (repair == :disabled) ? "" : "autonomy:\n  repair: allowed\n"
    autonomy += "  submit: allowed\n" if submit
    make_repo(files: {
      "lib/calc.rb" => BROKEN_LIB,
      "check.rb" => CHECK,
      ".reanimator.yml" => <<~YAML
        version: 1
        intent: maintain
        profile: generic
        #{autonomy}acceptance:
          protected_paths: [check.rb]
          checks:
            - id: arithmetic
              claim: "add(2, 2) equals 4."
              run: "ruby -Ilib check.rb"
              required: true
      YAML
    })
  end

  def run_for(path, **kwargs)
    contract = Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(path)).resolve
    described_class.new(contract, **kwargs).run
  end

  it "is a healthy no-op when all required criteria pass" do
    path = make_repo(files: {
      ".reanimator.yml" => "version: 1\nintent: maintain\nprofile: generic\nautonomy:\n  repair: allowed\n" \
        "acceptance:\n  checks:\n    - id: ok\n      run: \"true\"\n      required: true\n"
    })
    expect(run_for(path).outcome).to eq(:no_op)
  end

  it "escalates when repair autonomy is not enabled" do
    run = run_for(broken_repo(repair: :disabled))
    expect(run.outcome).to eq(:escalation)
    expect(run.reason).to include("Repair is not enabled")
  end

  it "proposes a verified draft PR without writing to the repository" do
    path = broken_repo(repair: :allowed)
    run = run_for(path)

    expect(run.outcome).to eq(:draft_pr)
    expect(run.pre_state).to eq(:at_risk)
    expect(run.post_state).to eq(:alive)
    expect(run.proposed_change.branch).to start_with("reanimator/repair-arithmetic-")
    expect(run.wrote_to_repository?).to be(false)
    # The original working tree is untouched: still broken on disk.
    expect(File.read(File.join(path, "lib/calc.rb"))).to include("a - b")
  end

  it "reports rather than proposes when the repair does not independently verify" do
    scripted = ScriptedAdapter.new(
      result: Reanimator::Agents::Result.new(plan: "tried", patch: Reanimator::Agents::Patch.write("lib/calc.rb", BROKEN_LIB))
    )
    allow(Reanimator::Agents).to receive(:for).and_return(scripted)
    # The provider commissions ready; it is the repair on THIS repo that fails
    # to verify, which is exactly the report (not safe-stop) outcome.
    allow(Reanimator::Commissioning::Test).to receive(:new).and_return(
      instance_double(Reanimator::Commissioning::Test,
        run: instance_double(Reanimator::Commissioning::Report, readiness: :ready))
    )

    run = run_for(broken_repo(repair: :allowed))
    expect(run.outcome).to eq(:report)
    expect(run.reason).to include("did not independently verify")
  end

  describe "submission" do
    def submitter(outcome)
      instance_double(Reanimator::Submitter).tap { |s| allow(s).to receive(:submit).and_return(outcome) }
    end

    let(:opened) { Reanimator::Submitter::Outcome.new("https://github.com/acme/widget/pull/7", nil) }

    it "does not submit unless the run asks to, even when the contract allows it" do
      fake = submitter(opened)
      run = run_for(broken_repo(repair: :allowed, submit: true), submitter: fake)

      expect(run.outcome).to eq(:draft_pr)
      expect(run).not_to be_submitted
      expect(fake).not_to have_received(:submit)
    end

    it "escalates with the verified change attached when the contract has not enabled submit" do
      fake = submitter(opened)
      run = run_for(broken_repo(repair: :allowed), submit: true, submitter: fake)

      expect(run.outcome).to eq(:escalation)
      expect(run.reason).to include("set autonomy: submit: allowed")
      expect(run.proposed_change).not_to be_nil
      expect(fake).not_to have_received(:submit)
    end

    it "escalates when the task class may only open an issue" do
      fake = submitter(opened)
      run = run_for(broken_repo(repair: :allowed, submit: true),
        task_class: :major_upgrade, submit: true, submitter: fake)

      expect(run.outcome).to eq(:escalation)
      expect(run.reason).to include("major_upgrade task class may only open an issue")
      expect(fake).not_to have_received(:submit)
    end

    it "opens the draft when both the contract and the run allow it" do
      fake = submitter(opened)
      path = broken_repo(repair: :allowed, submit: true)
      run = run_for(path, submit: true, submitter: fake)

      expect(run.outcome).to eq(:draft_pr)
      expect(run.pull_request_url).to eq("https://github.com/acme/widget/pull/7")
      expect(run.wrote_to_repository?).to be(true)
      expect(fake).to have_received(:submit).with(run.proposed_change, elevated_review: false)
      expect(File.read(File.join(path, "lib/calc.rb"))).to include("a - b")
      expect(Reanimator::Reports::Run.new(run).render).to include("DRAFT PR (submitted)", "Draft PR: https://github.com/acme/widget/pull/7")
    end

    it "escalates with the submitter's reason when submission is refused" do
      refused = Reanimator::Submitter::Outcome.new(nil, "no GitHub token; set REANIMATOR_GITHUB_TOKEN")
      run = run_for(broken_repo(repair: :allowed, submit: true), submit: true, submitter: submitter(refused))

      expect(run.outcome).to eq(:escalation)
      expect(run.reason).to eq("The repair verified but was not submitted: no GitHub token; set REANIMATOR_GITHUB_TOKEN.")
      expect(run).not_to be_submitted
    end
  end

  it "safely stops when no ready agent is available" do
    allow(Reanimator::Agents).to receive(:for).and_return(ScriptedAdapter.new(result: nil, available: false))
    run = run_for(broken_repo(repair: :allowed))
    expect(run.outcome).to eq(:safe_stop)
  end
end
