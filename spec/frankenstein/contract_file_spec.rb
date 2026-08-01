# frozen_string_literal: true

RSpec.describe Frankenstein::ContractFile do
  it "loads the minimal declaration from a repository" do
    root = make_repo(files: {".frankenstein.yml" => "version: 1\nintent: maintain\nprofile: ruby-gem\n"})
    file = described_class.load(root)

    expect(file.version).to eq(1)
    expect(file.intent).to eq(:maintain)
    expect(file.profile).to eq(:"ruby-gem")
  end

  it "returns nil when no contract file is present" do
    expect(described_class.load(make_repo)).to be_nil
  end

  it "round-trips a contract hash without semantic loss" do
    original = {
      version: 1, intent: :maintain, profile: :"rails-app",
      autonomy: {observe: :automatic, merge: :disabled},
      acceptance: {checks: [{id: :tests, run: "bin/rails test", required: true}]}
    }

    reparsed = described_class.new(YAML.safe_load(described_class.dump(original)))

    expect(reparsed.intent).to eq(:maintain)
    expect(reparsed.profile).to eq(:"rails-app")
    expect(reparsed.autonomy).to eq(observe: "automatic", merge: "disabled")
    expect(reparsed.acceptance[:checks].first).to include(id: "tests", run: "bin/rails test")
  end

  it "raises a clear error on invalid intent" do
    root = make_repo(files: {".frankenstein.yml" => "version: 1\nintent: destroy\n"})
    expect { described_class.load(root) }.to raise_error(Frankenstein::ContractError, /destroy/)
  end

  it "raises a clear error on malformed YAML" do
    root = make_repo(files: {".frankenstein.yml" => "version: 1\nintent: [unterminated\n"})
    expect { described_class.load(root) }.to raise_error(Frankenstein::ContractError, /valid YAML/)
  end
end
