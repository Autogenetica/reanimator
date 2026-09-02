# frozen_string_literal: true

RSpec.describe Frankenstein::Family::GateRunner do
  def family_with(check:, downstream_files: {"lib/x.rb" => "x"}, downstream_path: :fixture)
    upstream, downstream = make_portfolio({"widget" => {"lib/w.rb" => "x"}, "widget-examples" => downstream_files})
    path = (downstream_path == :fixture) ? downstream : downstream_path

    edge = Frankenstein::Relationship.new(from: "widget-examples", to: "widget", type: :compatibility_suite)
    Frankenstein::Family.new(
      id: :widget,
      members: [
        Frankenstein::Family::Member.new("widget", :library, upstream),
        Frankenstein::Family::Member.new("widget-examples", :compatibility_suite, path)
      ],
      gates: [Frankenstein::Family::Gate.new(on: "widget", requires_repository: "widget-examples", check: check)],
      relationships: [edge]
    )
  end

  it "plans rather than runs by default" do
    result = described_class.new(family_with(check: "true")).run.first
    expect(result.status).to eq(:planned)
    expect(result.detail).to include("Would run true in widget-examples")
  end

  it "verifies a downstream check that passes" do
    result = described_class.new(family_with(check: "true"), execute: true).run.first
    expect(result).to be_verified
    expect(result.detail).to include("passed in widget-examples")
  end

  it "names the exact edge that broke, not just the repository" do
    result = described_class.new(family_with(check: "false"), execute: true).run.first
    expect(result).to be_failed
    expect(result.edge).to eq("widget -> widget-examples (compatibility suite)")
  end

  it "runs the downstream check in a disposable copy, never its working tree" do
    _upstream, downstream = make_portfolio({"widget" => {}, "widget-examples" => {"lib/x.rb" => "x"}})
    family = family_with(check: "touch sentinel.txt", downstream_path: downstream)

    expect(described_class.new(family, execute: true).run.first).to be_verified
    expect(File.exist?(File.join(downstream, "sentinel.txt"))).to be(false)
  end

  it "falls back to the downstream member's own smoke script" do
    family = family_with(check: nil, downstream_files: {"bin/smoke" => "#!/bin/sh\nexit 0\n"})
    expect(described_class.new(family).run.first.detail).to include("Would run bin/smoke")
  end

  it "reports missing evidence when the edge has nothing to prove it" do
    family = family_with(check: nil, downstream_files: {"README.md" => "just docs"})
    result = described_class.new(family).run.first
    expect(result.status).to eq(:missing_evidence)
    expect(result.detail).to include("unverifiable")
  end

  it "reports missing evidence when the downstream member has no local checkout" do
    family = family_with(check: "true", downstream_path: nil)
    expect(described_class.new(family).run.first.detail).to include("No local checkout")
  end
end
