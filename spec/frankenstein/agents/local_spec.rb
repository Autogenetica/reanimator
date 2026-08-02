# frozen_string_literal: true

RSpec.describe Frankenstein::Agents::Local do
  def task_for(files, allowed: ["lib/**", "*.rb"], protected_paths: [])
    workspace = make_repo(files: files)
    objective = Frankenstein::AcceptanceCriterion.new(
      id: :arithmetic, claim: "add(2, 2) equals 4.", evaluator: :command, run: "ruby -Ilib check.rb"
    )
    Frankenstein::Agents::RepairTask.new(
      objective: objective, workspace: workspace, evidence: nil,
      constraints: {allowed_paths: allowed, protected_paths: protected_paths}
    )
  end

  let(:adapter) { described_class.new(Frankenstein::AgentConnection.local) }

  it "is always available and stays off the network" do
    expect(adapter.available?).to be(true)
    expect(adapter.capabilities).not_to include(Frankenstein::Agents::Capability::NETWORK)
  end

  it "produces a structured plan and patch for a recognized defect" do
    result = adapter.repair(task_for({"lib/calc.rb" => "def add(a, b)\n  a - b\nend\n"}))

    expect(result.structured?).to be(true)
    expect(result.plan).to include("addition")
    edit = result.patch.edits.first
    expect(edit.path).to eq("lib/calc.rb")
    expect(edit.contents).to include("a + b")
  end

  it "will not touch a protected path even when it holds the defect" do
    result = adapter.repair(
      task_for({"lib/calc.rb" => "def add(a, b)\n  a - b\nend\n"}, protected_paths: ["lib/**"])
    )
    expect(result.structured?).to be(false)
  end

  it "returns an unstructured result when nothing matches" do
    result = adapter.repair(task_for({"lib/calc.rb" => "def multiply(a, b) = a * b\n"}))
    expect(result.structured?).to be(false)
    expect(result.message).to include("No local strategy matched")
  end
end
