# frozen_string_literal: true

RSpec.describe Reanimator::SecurityControl do
  def discovery_with(*keys)
    facts = keys.map do |key|
      Reanimator::DiscoveredFact.new(
        key: key, category: :security_controls, claim: "#{key} is present.",
        provenance: Reanimator::Provenance.new(source: ".github/workflows", method: :action_fingerprint)
      )
    end
    Reanimator::DiscoveryResult.new(repository: nil, facts: facts)
  end

  it "names an obligation rather than a tool, so any accepted fingerprint satisfies it" do
    control = described_class.fetch(:dependency_review)
    bundler = control.evidence_in(discovery_with(:security_bundler_dependency_audit))
    dependabot = control.evidence_in(discovery_with(:dependabot))

    expect(bundler.key).to eq(:security_bundler_dependency_audit)
    expect(dependabot.key).to eq(:dependabot)
  end

  it "finds no evidence when none of its fingerprints are present" do
    control = described_class.fetch(:secret_scanning)
    expect(control.evidence_in(discovery_with(:dependabot, :codeowners))).to be_nil
  end

  it "owns the criterion id it is graded under, namespaced and without stuttering" do
    expect(described_class.fetch(:dependency_review).criterion_id).to eq(:"security-dependency-review")
    expect(described_class.fetch(:security_policy).criterion_id).to eq(:"security-policy")
  end

  it "points at a remedy instead of only reporting the gap" do
    expect(described_class.fetch(:secret_scanning).remedy).to include("gitleaks")
  end

  it "refuses an unknown control by name" do
    expect { described_class.fetch(:vibes) }
      .to raise_error(Reanimator::UnknownError, /Unknown security control :vibes/)
  end

  it "registers every control a posture can require" do
    required = Reanimator::SecurityPosture::OBLIGATIONS.values.flat_map(&:keys).uniq
    expect(required - described_class.ids).to be_empty
  end
end
