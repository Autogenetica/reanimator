# frozen_string_literal: true

RSpec.describe Reanimator::Family do
  it "parses the section 10 family-policy shape" do
    family = described_class.from_declaration(
      {
        id: :agentic,
        members: {
          "codenamev/agentic": {role: "library"},
          "codenamev/agentic-examples": {role: "compatibility-suite"}
        },
        gates: [
          {on: "codenamev/agentic", require: {repository: "codenamev/agentic-examples", check: "bin/smoke"}}
        ]
      },
      paths: {"codenamev/agentic" => "/tmp/agentic"}
    )

    expect(family.id).to eq(:agentic)
    expect(family.size).to eq(2)
    expect(family.member("codenamev/agentic").path).to eq("/tmp/agentic")
    # "compatibility-suite" in YAML becomes the :compatibility_suite role.
    expect(family.with_role(:compatibility_suite).map(&:full_name)).to eq(["codenamev/agentic-examples"])

    gate = family.gates.first
    expect(gate.check).to eq("bin/smoke")
    expect(gate.inferred_check?).to be(false)
    expect(gate.requires_repository).to eq("codenamev/agentic-examples")
  end

  it "requires an id" do
    expect { described_class.from_declaration({members: {}}) }
      .to raise_error(Reanimator::ContractError, /id/)
  end

  it "finds the edge between two members so a failure can name it" do
    edge = Reanimator::Relationship.new(from: "o/b", to: "o/a", type: :compatibility_suite)
    family = described_class.new(id: :a, relationships: [edge])
    expect(family.relationship_between("o/a", "o/b")).to eq(edge)
    expect(family.relationship_between("o/b", "o/a")).to be_nil
  end

  it "reports membership" do
    family = described_class.new(id: :a, members: [described_class::Member.new("o/a", :library, "/tmp/a")])
    expect(family.member?("o/a")).to be(true)
    expect(family.member?("o/z")).to be(false)
  end
end
