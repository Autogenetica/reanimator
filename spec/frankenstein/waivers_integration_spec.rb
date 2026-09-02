# frozen_string_literal: true

RSpec.describe "waivers in a baseline" do
  def baseline_for(waiver_yaml, execute: true)
    path = make_repo(files: {
      ".frankenstein.yml" => <<~YAML
        version: 1
        intent: maintain
        profile: generic
        acceptance:
          checks:
            - id: must
              claim: "the invariant holds"
              run: "false"
              required: true
        #{waiver_yaml}
      YAML
    })
    contract = Frankenstein::EffectivePolicyResolver.new(Frankenstein::Repository.at(path)).resolve
    Frankenstein::BaselineRunner.new(contract, execute: execute).run
  end

  it "records a failing required criterion as accepted risk when actively waived" do
    baseline = baseline_for(<<~YAML)
      waivers:
        - target: must
          reason: "known-flaky upstream; tracked in TICKET-42"
          expires: 2999-01-01
    YAML

    must = baseline.result_for(:must)
    expect(must).to be_accepted_risk
    expect(must.detail).to include("TICKET-42")
    # Accepted risk does not block, and is kept out of the vitality rate.
    expect(baseline.state.to_sym).to eq(:alive)
    expect(baseline.unresolved_required).to be_empty
    expect(baseline.accepted_risks.map { |r| r.criterion.id }).to eq([:must])
    expect(baseline.verified_vitality_rate).to eq(1.0)
  end

  it "fails closed when the waiver has expired" do
    baseline = baseline_for(<<~YAML)
      waivers:
        - target: must
          reason: "lapsed acceptance"
          expires: 2000-01-01
    YAML

    expect(baseline.result_for(:must)).to be_failed
    expect(baseline.state.to_sym).to eq(:at_risk)
    expect(baseline.accepted_risks).to be_empty
  end

  it "leaves an unwaived failure blocking" do
    baseline = baseline_for("")
    expect(baseline.result_for(:must)).to be_failed
    expect(baseline.state.to_sym).to eq(:at_risk)
  end
end
