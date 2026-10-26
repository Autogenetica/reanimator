# frozen_string_literal: true

RSpec.describe Reanimator::Waiver do
  def build(**overrides)
    described_class.new(target: :tests, reason: "tracked in TICKET-1", **overrides)
  end

  it "covers its target criterion" do
    expect(build.covers?(:tests)).to be(true)
    expect(build.covers?("tests")).to be(true)
    expect(build.covers?(:build)).to be(false)
  end

  it "is active indefinitely without an expiry" do
    expect(build(expires: nil).active?).to be(true)
  end

  it "fails closed once expired" do
    waiver = build(expires: "2020-01-01")
    expect(waiver.active?(now: Time.new(2019, 12, 31))).to be(true)
    expect(waiver.active?(now: Time.new(2020, 1, 2))).to be(false)
    expect(waiver.expired?(now: Time.new(2020, 1, 2))).to be(true)
  end

  it "accepts a Date, Time, or string expiry" do
    expect(build(expires: Date.new(2030, 1, 1)).expires).to be_a(Time)
    expect(build(expires: "2030-06-01").expires.year).to eq(2030)
  end

  it "insists on a reason so accepted risk is attributable" do
    expect { build(reason: "  ") }.to raise_error(Reanimator::ContractError, /reason/)
  end

  it "rejects an unparseable expiry" do
    expect { build(expires: "someday") }.to raise_error(Reanimator::ContractError, /expires/)
  end
end
