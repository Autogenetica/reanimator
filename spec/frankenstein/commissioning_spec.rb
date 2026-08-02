# frozen_string_literal: true

RSpec.describe Frankenstein::Commissioning::Test do
  # ScriptedAdapter lives in spec/support so it is not a constant defined inside
  # this example group's block.

  def patch(path, contents)
    Frankenstein::Agents::Patch.write(path, contents)
  end

  def result(plan:, patch:)
    Frankenstein::Agents::Result.new(plan: plan, patch: patch)
  end

  it "marks the local agent ready by independently verifying its repair" do
    report = described_class.new(Frankenstein::Agents.for(Frankenstein::AgentConnection.local)).run

    expect(report.readiness).to eq(:ready)
    expect(report.pre_state).to eq(:at_risk)
    expect(report.post_state).to eq(:alive)
    expect(report.proven_without_writes?).to be(true)
  end

  it "reports unavailable when the adapter cannot run" do
    adapter = ScriptedAdapter.new(result: nil, available: false)
    expect(described_class.new(adapter).run.readiness).to eq(:unavailable)
  end

  it "reports incompatible when no structured plan and patch is produced" do
    adapter = ScriptedAdapter.new(result: Frankenstein::Agents::Result.new)
    report = described_class.new(adapter).run
    expect(report.readiness).to eq(:incompatible)
    expect(report.reason).to include("no structured plan and patch")
  end

  it "refuses a patch that edits a protected verifier path (anti-gaming)" do
    adapter = ScriptedAdapter.new(result: result(plan: "sneaky", patch: patch("check.rb", "exit 0")))
    report = described_class.new(adapter).run
    expect(report.readiness).to eq(:incompatible)
    expect(report.reason).to include("protected")
  end

  it "marks a structured-but-ineffective repair degraded" do
    still_broken = "module Calc\n  module_function\n  def add(a, b)\n    a - b\n  end\nend\n"
    adapter = ScriptedAdapter.new(result: result(plan: "tried", patch: patch("lib/calc.rb", still_broken)))
    report = described_class.new(adapter).run
    expect(report.readiness).to eq(:degraded)
    expect(report.reason).to include("did not resolve")
  end
end
