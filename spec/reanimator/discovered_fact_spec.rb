# frozen_string_literal: true

RSpec.describe Reanimator::DiscoveredFact do
  def build(**overrides)
    described_class.new(key: :rspec, category: :commands, claim: "Tests run with RSpec.",
      provenance: Reanimator::Provenance.new(source: ".rspec", method: :file_present), **overrides)
  end

  it "starts as a proposal" do
    expect(build.status).to eq(:proposed)
    expect(build.active?).to be(true)
  end

  it "becomes declared policy when accepted" do
    expect(build.accept.status).to eq(:accepted)
    expect(build.accept.accepted?).to be(true)
  end

  it "drops out of the contract when rejected" do
    rejected = build.reject
    expect(rejected.status).to eq(:rejected)
    expect(rejected.active?).to be(false)
  end

  it "records a human edit as edited with the new value" do
    edited = build.edit("bundle exec rake")
    expect(edited.status).to eq(:edited)
    expect(edited.value).to eq("bundle exec rake")
  end

  it "rejects unknown categories and statuses" do
    expect { build(category: :nonsense) }.to raise_error(Reanimator::UnknownError)
    expect { build(status: :nonsense) }.to raise_error(Reanimator::UnknownError)
  end

  it "always carries provenance in its hash" do
    expect(build.to_h[:provenance]).to include(source: ".rspec", method: :file_present)
  end
end
