# frozen_string_literal: true

RSpec.describe Reanimator::EffectivePolicyResolver do
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
      ".reanimator.yml" => "version: 1\nintent: preserve\nprofile: rails-legacy\n"
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

  it "carries active waivers and drops expired ones" do
    contract = resolve(files: {".reanimator.yml" => <<~YAML})
      version: 1
      intent: maintain
      profile: generic
      waivers:
        - target: boot
          reason: "accepted"
          expires: 2999-01-01
        - target: old
          reason: "lapsed"
          expires: 2000-01-01
    YAML
    expect(contract.waivers.size).to eq(2)
    expect(contract.waiver_for(:boot)).not_to be_nil
    expect(contract.waiver_for(:old)).to be_nil
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
        ".reanimator.yml" => "version: 1\nintent: maintain\nprofile: ruby-gem\nautonomy:\n  merge: enabled\n"
      })
      expect(contract.autonomy[:merge]).to eq(:disabled)
      expect(contract.notes.join).to match(/merge/i)
    end

    it "always protects verifier and contract paths, even without a declaration" do
      contract = resolve(files: {"Gemfile" => "gemspec\n", "widget.gemspec" => "x"})
      expect(contract.protected_paths).to include(".reanimator.yml", ".github/workflows/**")
    end
  end

  describe "merging the layers that contribute obligations" do
    it "lets an owner declaration replace a criterion the posture supplied" do
      contract = resolve(files: {".reanimator.yml" => <<~YAML})
        version: 1
        intent: maintain
        profile: generic
        security:
          posture: local
        acceptance:
          checks:
            - id: security-secret-scanning
              claim: "our own scanner runs in the pre-commit hook"
              run: "bin/scan-secrets"
      YAML
      matching = contract.criteria.select { |c| c.id == :"security-secret-scanning" }

      expect(matching.size).to eq(1)
      expect(matching.first.evaluator).to eq(:command)
      expect(matching.first.owner).to eq("repository")
    end

    it "lets an owner declaration replace a profile default rather than duplicating it" do
      contract = resolve(files: {
        "Gemfile" => "gemspec\n", "widget.gemspec" => "x",
        ".reanimator.yml" => <<~YAML
          version: 1
          intent: maintain
          profile: ruby-gem
          acceptance:
            checks:
              - id: tests
                claim: "the suite passes under our runner"
                run: "bin/test"
        YAML
      })
      matching = contract.criteria.select { |c| c.id == :tests }

      expect(matching.size).to eq(1)
      expect(matching.first.run).to eq("bin/test")
    end

    it "adds the posture's security obligations to whatever the profile already asks for" do
      contract = resolve(files: {
        "Gemfile" => "gemspec\n", "widget.gemspec" => "x",
        ".reanimator.yml" => "version: 1\nintent: maintain\nprofile: ruby-gem\nsecurity:\n  posture: strict\n"
      })
      ids = contract.criteria.map(&:id)

      expect(ids).to include(:tests, :build)
      expect(ids).to include(:"security-policy", :"security-dependency-review", :"security-secret-scanning")
    end
  end

  it "produces a stable policy version fingerprint" do
    files = {"Gemfile" => "gemspec\n", "widget.gemspec" => "x"}
    a = described_class.new(Reanimator::Repository.at(make_repo(files: files))).resolve
    b = described_class.new(Reanimator::Repository.at(make_repo(files: files))).resolve
    expect(a.policy_version).to eq(b.policy_version)
    expect(a.policy_version).to start_with("ruby-gem@")
  end
end
