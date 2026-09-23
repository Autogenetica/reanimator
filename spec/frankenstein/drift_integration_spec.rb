# frozen_string_literal: true

RSpec.describe "configuration drift over a real repository" do
  # Re-resolves the contract from disk after the declaration is edited, which
  # is how drift actually arrives: nobody announces it.
  def snapshot_of(path) = Frankenstein.snapshot(path)

  def declare(path, yaml) = File.write(File.join(path, ".frankenstein.yml"), yaml)

  let(:contract_yaml) do
    <<~YAML
      version: 1
      intent: maintain
      profile: generic
      acceptance:
        checks:
          - id: tests
            claim: "the suite passes"
            run: "bundle exec rspec"
            required: true
    YAML
  end

  let(:path) { make_repo(files: {".frankenstein.yml" => contract_yaml, "README.md" => "# widget"}) }

  it "sees nothing when the repository has not moved" do
    recorded = snapshot_of(path)
    expect(Frankenstein::DriftDetector.between(recorded, snapshot_of(path))).not_to be_drifted
  end

  it "records a snapshot to disk and detects drift against it later" do
    recorded = File.join(path, "snapshot.json")
    File.write(recorded, snapshot_of(path).to_json)

    declare(path, contract_yaml.sub("required: true", "required: false"))
    report = Frankenstein.drift(path, since: recorded)

    expect(report.requires_review?).to be(true)
    expect(report.policy_changes.map(&:summary)).to eq(["criterion tests required: true → false"])
  end

  it "stays quiet when only the command spelling moved" do
    recorded = snapshot_of(path)
    declare(path, contract_yaml.sub("bundle exec rspec", "bin/rspec"))

    report = Frankenstein::DriftDetector.between(recorded, snapshot_of(path))
    expect(report).to be_drifted
    expect(report.requires_review?).to be(false)
    expect(Frankenstein::Reports::Drift.new(report).render).to include("bundle exec rspec → bin/rspec")
  end

  # The evidence half of section 06: neither of these edits touches
  # .frankenstein.yml, and both still have to surface as policy changes.
  it "notices a security gate disappearing from the repository itself" do
    with_gate = make_repo(files: {
      ".frankenstein.yml" => contract_yaml,
      ".github/dependabot.yml" => "version: 2\nupdates: []\n"
    })
    recorded = snapshot_of(with_gate)
    FileUtils.rm(File.join(with_gate, ".github/dependabot.yml"))

    report = Frankenstein::DriftDetector.between(recorded, snapshot_of(with_gate))
    expect(report.policy_changes.map(&:summary)).to include("security control removed: dependabot")
  end

  it "notices the CI runtime matrix narrowing" do
    workflow = ->(versions) {
      <<~YAML
        name: CI
        on: [push]
        jobs:
          test:
            strategy:
              matrix:
                ruby: #{versions.inspect}
            steps:
              - uses: actions/checkout@v4
      YAML
    }
    repo = make_repo(files: {".frankenstein.yml" => contract_yaml, ".github/workflows/ci.yml" => workflow.call(%w[3.2 3.3 3.4])})
    recorded = snapshot_of(repo)
    File.write(File.join(repo, ".github/workflows/ci.yml"), workflow.call(%w[3.4]))

    report = Frankenstein::DriftDetector.between(recorded, snapshot_of(repo))
    expect(report.policy_changes.map(&:summary)).to contain_exactly(
      "supported runtime removed: 3.2", "supported runtime removed: 3.3"
    )
  end

  it "refuses to compare a snapshot from a different repository" do
    other = snapshot_of(make_repo(files: {"README.md" => "# other"}))
    recorded = File.join(path, "other.json")
    File.write(recorded, other.to_json)

    expect { Frankenstein.drift(path, since: recorded) }
      .to raise_error(Frankenstein::ContractError, /only meaningful within one repository/)
  end
end
