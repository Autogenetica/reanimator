# frozen_string_literal: true

RSpec.describe Reanimator::PermissionModel do
  def contract_with(autonomy_yaml)
    root = make_repo(files: {
      "Gemfile" => "gemspec\n", "widget.gemspec" => "x",
      ".reanimator.yml" => "version: 1\nintent: maintain\nprofile: ruby-gem\n#{autonomy_yaml}"
    })
    Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(root)).resolve
  end

  it "clamps everything above diagnose when repair and submit are disabled" do
    contract = contract_with("")
    resolution = described_class.new(contract).resolve(:patch_dependency)

    expect(resolution.actions[:repair]).to eq(:off)
    expect(resolution.actions[:submit]).to eq(:off)
    expect(resolution.max_action).to eq(:diagnose)
  end

  it "lets task-class defaults through once the contract enables the rungs" do
    contract = contract_with("autonomy:\n  repair: allowed\n  submit: allowed\n")
    resolution = described_class.new(contract).resolve(:patch_dependency)

    expect(resolution.actions[:repair]).to eq(:allowed)
    expect(resolution.actions[:submit]).to eq(:allowed)
  end

  it "keeps merge off even when a contract tries to enable it (safety floor)" do
    contract = contract_with("autonomy:\n  repair: allowed\n  submit: allowed\n  merge: enabled\n")
    resolution = described_class.new(contract).resolve(:critical_security)
    expect(resolution.actions[:merge]).to eq(:off)
  end

  it "flags elevated review for verifier modification" do
    resolution = described_class.new(contract_with("")).resolve(:verifier_modification)
    expect(resolution.elevated_review?).to be(true)
  end
end
