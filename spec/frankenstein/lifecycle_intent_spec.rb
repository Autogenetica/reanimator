# frozen_string_literal: true

RSpec.describe Frankenstein::LifecycleIntent do
  it "exposes the seven canonical intents" do
    expect(described_class::ALL.keys).to contain_exactly(
      :maintain, :monitor, :preserve, :incubate, :retire, :upstream, :ignore
    )
  end

  it "fetches an intent with its promise and default activity" do
    intent = described_class.fetch(:maintain)
    expect(intent.promise).to include("runnable")
    expect(intent.default_activity).to include("verification")
  end

  it "treats only ignore as creating no obligation" do
    expect(described_class.fetch(:ignore).creates_obligation?).to be(false)
    expect(described_class.fetch(:maintain).creates_obligation?).to be(true)
  end

  it "accepts strings and symbols and validates unknown keys" do
    expect(described_class.fetch("preserve").key).to eq(:preserve)
    expect(described_class.valid?(:bogus)).to be(false)
    expect { described_class.fetch(:bogus) }.to raise_error(Frankenstein::UnknownError)
  end
end
