# frozen_string_literal: true

RSpec.describe Frankenstein::Relationship do
  it "names the exact edge, upstream to dependent" do
    edge = described_class.new(from: "o/agentic-examples", to: "o/agentic", type: :compatibility_suite)
    expect(edge.label).to eq("o/agentic -> o/agentic-examples (compatibility suite)")
    expect(edge.description).to include("validates this project's public claims")
  end

  it "maps each type to the role the dependent side plays" do
    expect(described_class.new(from: "a", to: "b", type: :compatibility_suite).role).to eq(:compatibility_suite)
    expect(described_class.new(from: "a", to: "b", type: :plugin_for).role).to eq(:plugin)
    expect(described_class.new(from: "a", to: "b", type: :deployment_example).role).to eq(:deployment_example)
  end

  it "carries the evidence for why the edge is believed" do
    edge = described_class.new(from: "a", to: "b", type: :plugin_for, evidence: "name a targets b")
    expect(edge.to_h).to include(evidence: "name a targets b")
  end

  it "rejects an unknown relationship type" do
    expect { described_class.new(from: "a", to: "b", type: :vibes) }
      .to raise_error(Frankenstein::UnknownError, /vibes/)
  end
end
