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

  # A snapshot file is ordinary input: anything on the machine can write it,
  # and a maintainer can point --since at the wrong path. Every one of these
  # used to escape as a raw TypeError, NoMethodError, or Errno backtrace.
  it "refuses a file that is valid JSON but is not a snapshot" do
    dir = make_repo
    {"array.json" => "[1,2,3]", "number.json" => "123", "null.json" => "null",
     "object.json" => '{"something": "else"}'}.each do |name, contents|
      path = File.join(dir, name)
      File.write(path, contents)
      expect { described_class.load(path) }
        .to raise_error(Frankenstein::ContractError, /not a contract snapshot/), "loading #{name}"
    end
  end

  it "refuses a path that cannot be read as a file" do
    expect { described_class.load(make_repo) }
      .to raise_error(Frankenstein::ContractError, /Could not read the contract snapshot/)
  end

  # "What was true then" stops being trustworthy the moment anyone can edit it,
  # and a bare freeze leaves the recorded collections writable.
  it "cannot be edited after it is recorded" do
    snapshot = described_class.of(contract_for(".frankenstein.yml" => "version: 1\nintent: maintain\nprofile: generic\n"))

    expect { snapshot.protected_paths << "anything" }.to raise_error(FrozenError)
    expect { snapshot.criteria.first[:required] = false }.to raise_error(FrozenError)
    expect { snapshot.support_matrix << "9.9" }.to raise_error(FrozenError)
  end

  it "does not freeze the contract it was recorded from" do
    contract = contract_for("README.md" => "# widget")
    described_class.of(contract)

    expect { contract.protected_paths << "config/**" }.not_to raise_error
  end

  it "refuses a missing or unreadable snapshot rather than comparing against nothing" do
    missing = File.join(make_repo, "absent.json")
    expect { described_class.load(missing) }.to raise_error(Frankenstein::ContractError, /No contract snapshot/)

    garbage = File.join(make_repo, "garbage.json")
    File.write(garbage, "not json at all")
    expect { described_class.load(garbage) }.to raise_error(Frankenstein::ContractError, /not a valid/)
  end
end
