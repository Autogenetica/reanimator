# frozen_string_literal: true

RSpec.describe Frankenstein::FamilyInference do
  def families_for(repositories)
    described_class.call(Frankenstein.inventory(make_portfolio(repositories)))
  end

  # The families the specification suggests for the codenamev portfolio.
  it "groups a project with its executable examples as a compatibility suite" do
    families = families_for({"agentic" => {"lib/a.rb" => "x"}, "agentic-examples" => {"lib/b.rb" => "x"}})

    family = families.find { |f| f.id == :agentic }
    expect(family.members.map(&:role)).to contain_exactly(:library, :compatibility_suite)
    expect(family.relationships.first.type).to eq(:compatibility_suite)
  end

  it "groups deployment examples under their parent project" do
    families = families_for({
      "slimer" => {"lib/s.rb" => "x"},
      "slimer-example-docker" => {"lib/d.rb" => "x"},
      "slimer-example-heroku" => {"lib/h.rb" => "x"}
    })

    family = families.find { |f| f.id == :slimer }
    expect(family.size).to eq(3)
    expect(family.relationships.map(&:type).uniq).to eq([:deployment_example])
  end

  it "treats a prefixed integration as a plugin for the project it targets" do
    families = families_for({"ups" => {"lib/u.rb" => "x"}, "ruby_llm-ups" => {"lib/r.rb" => "x"}})

    family = families.find { |f| f.id == :ups }
    expect(family.relationships.first.type).to eq(:plugin_for)
    expect(family.with_role(:plugin).map(&:full_name).first).to include("ruby_llm-ups")
  end

  it "creates a gate per edge so every dependence has something that proves it" do
    families = families_for({"agentic" => {"lib/a.rb" => "x"}, "agentic-examples" => {"lib/b.rb" => "x"}})
    gate = families.find { |f| f.id == :agentic }.gates.first

    expect(gate.on).to include("agentic")
    expect(gate.requires_repository).to include("agentic-examples")
    expect(gate.inferred_check?).to be(true)
  end

  it "stays conservative: unrelated repositories form no family" do
    families = families_for({"podcast-buddy" => {"lib/p.rb" => "x"}, "meeting-buddy" => {"lib/m.rb" => "x"}})
    expect(families).to be_empty
  end

  it "lets a declared family win over inference" do
    families = families_for({
      "widget" => {".frankenstein.yml" => "version: 1\nintent: maintain\nfamily:\n  id: bespoke\n  role: application\n"},
      "widget-examples" => {"lib/w.rb" => "x"}
    })

    expect(families.map(&:id)).to include(:bespoke)
    bespoke = families.find { |f| f.id == :bespoke }
    expect(bespoke.members.first.role).to eq(:application)
    # No competing family is invented around a repository whose owner has
    # already placed it: declaration wins on both ends of the edge.
    expect(families.map(&:id)).not_to include(:widget)
  end
end
