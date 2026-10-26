# frozen_string_literal: true

RSpec.describe Reanimator::Agents::Constraints do
  it "refuses a protected path at any depth" do
    constraints = described_class.new(protected_paths: [".github/workflows/**"])
    expect(constraints.may_edit?(".github/workflows/ci.yml")).to be(false)
    expect(constraints.may_edit?(".github/workflows/nested/deploy.yml")).to be(false)
  end

  it "allows nested paths under an allowed glob and denies outside it" do
    constraints = described_class.new(allowed_paths: ["lib/**"])
    expect(constraints.may_edit?("lib/calc.rb")).to be(true)
    expect(constraints.may_edit?("lib/deep/nested/thing.rb")).to be(true)
    expect(constraints.may_edit?("app/models/user.rb")).to be(false)
  end

  it "lets protection win over an allow rule" do
    constraints = described_class.new(allowed_paths: ["**/*"], protected_paths: [".reanimator.yml"])
    expect(constraints.may_edit?(".reanimator.yml")).to be(false)
    expect(constraints.may_edit?("lib/calc.rb")).to be(true)
  end

  it "allows anything when no allow-list is declared" do
    expect(described_class.new.may_edit?("anywhere/at/all.rb")).to be(true)
  end

  describe ".from" do
    it "coerces the plain hash shape, ignoring unknown keys" do
      constraints = described_class.from(allowed_paths: ["lib/**"], max_cost_usd: 5, nonsense: true)
      expect(constraints).to be_a(described_class)
      expect(constraints.allowed_paths).to eq(["lib/**"])
      expect(constraints.max_cost_usd).to eq(5)
    end

    it "passes an existing instance through, and treats nil as empty" do
      existing = described_class.new(allowed_paths: ["a"])
      expect(described_class.from(existing)).to equal(existing)
      expect(described_class.from(nil).allowed_paths).to eq([])
    end
  end

  it "is immutable" do
    expect(described_class.new).to be_frozen
  end
end
