# frozen_string_literal: true

RSpec.describe Reanimator::Agents::RepairTask do
  def task(allowed:, protected_paths:)
    described_class.new(
      objective: Reanimator::AcceptanceCriterion.new(id: :x, claim: "x", evaluator: :command),
      workspace: "/tmp", evidence: nil,
      constraints: {allowed_paths: allowed, protected_paths: protected_paths}
    )
  end

  it "refuses a protected path at any depth, not just the top level" do
    subject = task(allowed: [], protected_paths: [".github/workflows/**"])
    expect(subject.may_edit?(".github/workflows/ci.yml")).to be(false)
    # The regression: a nested workflow must also be protected.
    expect(subject.may_edit?(".github/workflows/nested/deploy.yml")).to be(false)
  end

  it "allows nested files under an allowed glob and denies outside it" do
    subject = task(allowed: ["lib/**"], protected_paths: [])
    expect(subject.may_edit?("lib/calc.rb")).to be(true)
    expect(subject.may_edit?("lib/deep/nested/thing.rb")).to be(true)
    expect(subject.may_edit?("app/models/user.rb")).to be(false)
  end

  it "lets protection win over an allow rule" do
    subject = task(allowed: ["**/*"], protected_paths: [".reanimator.yml"])
    expect(subject.may_edit?(".reanimator.yml")).to be(false)
    expect(subject.may_edit?("lib/calc.rb")).to be(true)
  end
end
