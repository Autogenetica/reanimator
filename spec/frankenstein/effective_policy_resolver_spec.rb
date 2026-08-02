# frozen_string_literal: true

RSpec.describe Frankenstein::EffectivePolicyResolver do
  def resolve(**kwargs)
    described_class.new(make_repository(**kwargs)).resolve
  end

  it "infers the profile and marks intent provisional when nothing is declared" do
    contract = resolve(files: {"Gemfile" => "gemspec\n", "widget.gemspec" => "x"})
    expect(contract.profile.id).to eq(:"ruby-gem")
    expect(contract.profile_source).to eq(:inferred)
    expect(contract.intent_confirmed?).to be(false)
  end

  it "lets an owner-declared contract win over inference" do
    contract = resolve(files: {
      "Gemfile" => "gemspec\n", "widget.gemspec" => "x",
      ".frankenstein.yml" => "version: 1\nintent: preserve\nprofile: rails-legacy\n"
    })
    expect(contract.profile.id).to eq(:"rails-legacy")
    expect(contract.profile_source).to eq(:declared)
    expect(contract.intent.to_sym).to eq(:preserve)
    expect(contract.intent_confirmed?).to be(true)
  end

  it "prefers the historical variant when a Rails app is to be preserved" do
    contract = described_class.new(
      make_repository(files: {
        "config/application.rb" => "class App < Rails::Application; end\n"
      }).tap { |r| r.intent = :preserve }
    ).resolve
    expect(contract.profile.id).to eq(:"rails-legacy")
  end

  it "substitutes discovered commands into the profile's criteria" do
    contract = resolve(files: {
      "Gemfile" => "gemspec\n", "widget.gemspec" => "x", ".rspec" => "--color\n"
    })
    tests = contract.criteria.find { |c| c.id == :tests }
    expect(tests.run).to eq("bundle exec rspec")
  end

  it "carries provenance from the discovered command onto the tests criterion" do
    contract = resolve(files: {
      "Gemfile" => "gemspec\n", "widget.gemspec" => "x", ".rspec" => "--color\n"
    })
    tests = contract.criteria.find { |c| c.id == :tests }
    expect(tests.provenance).not_to be_nil
    expect(tests.provenance.source).to eq(".rspec")
  end

  describe "the non-bypassable safety floor" do
    it "clamps a contract that tries to enable merge, and records the clamp" do
      contract = resolve(files: {
        "Gemfile" => "gemspec\n", "widget.gemspec" => "x",
        ".frankenstein.yml" => "version: 1\nintent: maintain\nprofile: ruby-gem\nautonomy:\n  merge: enabled\n"
      })
      expect(contract.autonomy[:merge]).to eq(:disabled)
      expect(contract.notes.join).to match(/merge/i)
    end

    it "always protects verifier and contract paths, even without a declaration" do
      contract = resolve(files: {"Gemfile" => "gemspec\n", "widget.gemspec" => "x"})
      expect(contract.protected_paths).to include(".frankenstein.yml", ".github/workflows/**")
    end
  end

  it "produces a stable policy version fingerprint" do
    files = {"Gemfile" => "gemspec\n", "widget.gemspec" => "x"}
    a = described_class.new(Frankenstein::Repository.at(make_repo(files: files))).resolve
    b = described_class.new(Frankenstein::Repository.at(make_repo(files: files))).resolve
    expect(a.policy_version).to eq(b.policy_version)
    expect(a.policy_version).to start_with("ruby-gem@")
  end
end
