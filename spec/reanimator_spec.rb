# frozen_string_literal: true

RSpec.describe Reanimator do
  it "has a version number" do
    expect(Reanimator::VERSION).not_to be_nil
  end

  describe "the read-only onboarding path" do
    let(:gem_repo) do
      make_repo(files: {
        "Gemfile" => "source 'https://rubygems.org'\ngemspec\n",
        "widget.gemspec" => "Gem::Specification.new { |s| s.required_ruby_version = '>= 3.1.0' }\n",
        ".rspec" => "--color\n",
        "README.md" => "# widget"
      })
    end

    it "discovers facts, resolves a contract, and baselines without touching source" do
      discovery = Reanimator.discover(gem_repo)
      expect(discovery.suggested_profile).to eq(:"ruby-gem")

      contract = Reanimator.contract(gem_repo)
      expect(contract).to be_a(Reanimator::EffectiveContract)
      expect(contract.autonomy[:merge]).to eq(:disabled)

      baseline = Reanimator.baseline(gem_repo)
      expect(baseline).to be_a(Reanimator::Baseline)
      expect(baseline.executed?).to be(false)
      # The promise: a first run without writing config, an agent, or write access.
      expect(baseline.to_h[:results]).not_to be_empty
    end

    it "honors an intent override" do
      contract = Reanimator.contract(gem_repo, intent: :preserve)
      expect(contract.intent.to_sym).to eq(:preserve)
      expect(contract.intent_confirmed?).to be(true)
    end

    it "classifies a set of paths into a portfolio" do
      portfolio = Reanimator.inventory([gem_repo])
      expect(portfolio).to be_a(Reanimator::Portfolio)
      expect(portfolio.size).to eq(1)
    end
  end

  it "raises a RepositoryError for a path that is not a directory" do
    expect { Reanimator.discover("/no/such/place") }.to raise_error(Reanimator::RepositoryError)
  end
end
