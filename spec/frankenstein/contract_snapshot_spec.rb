# frozen_string_literal: true

RSpec.describe Frankenstein::ContractSnapshot do
  def contract_for(files)
    Frankenstein::EffectivePolicyResolver.new(Frankenstein::Repository.at(make_repo(files: files))).resolve
  end

  it "captures what a repository is required to prove" do
    snapshot = described_class.of(contract_for(
      ".frankenstein.yml" => <<~YAML,
        version: 1
        intent: maintain
        profile: generic
        acceptance:
          checks:
            - id: must
              claim: "the invariant holds"
              run: "true"
              required: true
        waivers:
          - target: must
            reason: "tracked in TICKET-1"
            expires: 2999-01-01
      YAML
      "README.md" => "# widget"
    ))

    expect(snapshot.intent).to eq(:maintain)
    expect(snapshot.profile).to eq(:generic)
    expect(snapshot.criterion_ids).to include(:must)
    expect(snapshot.criterion(:must)).to include(run: "true", required: true)
    expect(snapshot.waiver_targets).to eq([:must])
  end

  # Section 06 names a removed security gate and a narrowed runtime matrix as
  # policy changes, and both live in discovered evidence rather than in the
  # declared file - so the snapshot has to carry evidence, not just declaration.
  it "captures discovered evidence, not only the declared contract" do
    snapshot = described_class.of(contract_for(
      "widget.gemspec" => <<~RUBY,
        Gem::Specification.new do |spec|
          spec.name = "widget"
          spec.version = "0.1.0"
          spec.required_ruby_version = ">= 3.1.0"
        end
      RUBY
      ".github/workflows/ci.yml" => <<~YAML,
        name: CI
        on: [push]
        jobs:
          test:
            strategy:
              matrix:
                ruby: ["3.2", "3.3"]
            steps:
              - uses: actions/checkout@v4
      YAML
      ".github/dependabot.yml" => "version: 2\nupdates: []\n"
    ))

    expect(snapshot.support_matrix).to eq(%w[3.2 3.3])
    expect(snapshot.security_controls).to include(:dependabot)
  end

  it "round-trips through JSON without losing its types" do
    original = described_class.of(contract_for(".frankenstein.yml" => "version: 1\nintent: preserve\nprofile: generic\n"))
    restored = described_class.from_h(JSON.parse(original.to_json))

    expect(restored.intent).to eq(:preserve)
    expect(restored.profile).to eq(original.profile)
    expect(restored.criterion_ids).to eq(original.criterion_ids)
    expect(restored.autonomy).to eq(original.autonomy)
    expect(restored.to_h).to eq(original.to_h)
  end

  it "reads a recorded snapshot from disk" do
    snapshot = described_class.of(contract_for("README.md" => "# widget"))
    path = File.join(make_repo, "snapshot.json")
    File.write(path, snapshot.to_json)

    expect(described_class.load(path).repository).to eq(snapshot.repository)
  end

  it "refuses a missing or unreadable snapshot rather than comparing against nothing" do
    missing = File.join(make_repo, "absent.json")
    expect { described_class.load(missing) }.to raise_error(Frankenstein::ContractError, /No contract snapshot/)

    garbage = File.join(make_repo, "garbage.json")
    File.write(garbage, "not json at all")
    expect { described_class.load(garbage) }.to raise_error(Frankenstein::ContractError, /not a valid/)
  end
end
