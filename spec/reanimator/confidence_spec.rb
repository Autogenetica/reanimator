# frozen_string_literal: true

RSpec.describe Reanimator::Confidence do
  it "orders low < medium < high" do
    expect(described_class::LOW).to be < described_class::HIGH
    expect([described_class::HIGH, described_class::LOW, described_class::MEDIUM].sort.map(&:to_sym))
      .to eq(%i[low medium high])
  end

  it "only preselects high confidence" do
    expect(described_class::HIGH.preselectable?).to be(true)
    expect(described_class::MEDIUM.preselectable?).to be(false)
  end

  it "never lets low confidence become an obligation directly" do
    expect(described_class::LOW.obligatable?).to be(false)
    expect(described_class::MEDIUM.obligatable?).to be(true)
  end

  it "coerces symbols and passes through instances" do
    expect(described_class[:high]).to eq(described_class::HIGH)
    expect(described_class[described_class::LOW]).to eq(described_class::LOW)
  end
end
