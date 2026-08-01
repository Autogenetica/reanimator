# frozen_string_literal: true

BROKEN_LIB = "module Calc\n  module_function\n  def add(a, b)\n    a - b\n  end\nend\n"
CHECK = %(require "calc"\nraise "broken" unless Calc.add(2, 2) == 4\n)

RSpec.describe Frankenstein::RepairRun do
  def broken_repo(repair: :disabled)
    autonomy = (repair == :disabled) ? "" : "autonomy:\n  repair: allowed\n"
    make_repo(files: {
      "lib/calc.rb" => BROKEN_LIB,
      "check.rb" => CHECK,
      ".frankenstein.yml" => <<~YAML
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
    contract = Frankenstein::EffectivePolicyResolver.new(Frankenstein::Repository.at(path)).resolve
    described_class.new(contract, **kwargs).run
  end

  it "is a healthy no-op when all required criteria pass" do
    path = make_repo(files: {
      ".frankenstein.yml" => "version: 1\nintent: maintain\nprofile: generic\nautonomy:\n  repair: allowed\n" \
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
    expect(run.proposed_change.branch).to start_with("frankenstein/repair-arithmetic-")
    expect(run.wrote_to_repository?).to be(false)
    # The original working tree is untouched: still broken on disk.
    expect(File.read(File.join(path, "lib/calc.rb"))).to include("a - b")
  end

  it "reports rather than proposes when the repair does not independently verify" do
    scripted = ScriptedAdapter.new(
      result: Frankenstein::Agents::Result.new(plan: "tried", patch: Frankenstein::Agents::Patch.write("lib/calc.rb", BROKEN_LIB))
    )
    allow(Frankenstein::Agents).to receive(:for).and_return(scripted)

    run = run_for(broken_repo(repair: :allowed))
    expect(run.outcome).to eq(:report)
    expect(run.reason).to include("did not independently verify")
  end

  it "safely stops when no ready agent is available" do
    allow(Frankenstein::Agents).to receive(:for).and_return(ScriptedAdapter.new(result: nil, available: false))
    run = run_for(broken_repo(repair: :allowed))
    expect(run.outcome).to eq(:safe_stop)
  end
end
