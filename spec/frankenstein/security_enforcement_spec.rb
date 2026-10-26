# frozen_string_literal: true

# Section 12 makes the security posture a first-class, named decision. These
# examples pin the behavior that makes it more than a label: the posture, not
# the project's shape, decides how much security evidence a repository has to
# show, and a repository with none of it can no longer read as fully alive
# under a posture that asks for it.
RSpec.describe "security posture enforcement" do
  def baseline_for(files)
    repository = Frankenstein::Repository.at(make_repo(files: files))
    contract = Frankenstein::EffectivePolicyResolver.new(repository).resolve
    Frankenstein::BaselineRunner.new(contract).run
  end

  def declaring(posture, extra = "")
    <<~YAML
      version: 1
      intent: maintain
      profile: generic
      security:
        posture: #{posture}
      #{extra}
    YAML
  end

  it "stops a repository with no security evidence from reading as fully alive under strict" do
    baseline = baseline_for({"README.md" => "# widget", ".frankenstein.yml" => declaring(:strict)})

    expect(baseline.state.to_sym).to eq(:unproven)
    expect(baseline.verified_vitality_rate).to eq(0.0)
    expect(baseline.unresolved_required.map { |r| r.criterion.id })
      .to contain_exactly(:"security-policy", :"security-dependency-review", :"security-secret-scanning")
  end

  it "reports the same gaps under balanced without blocking, because the posture is the knob" do
    baseline = baseline_for({"README.md" => "# widget", ".frankenstein.yml" => declaring(:balanced)})

    expect(baseline.state.to_sym).to eq(:alive)
    expect(baseline.unresolved_required).to be_empty
    expect(baseline.result_for(:"security-secret-scanning").status).to eq(:missing_evidence)
    expect(baseline.result_for(:"security-secret-scanning").detail).to include("gitleaks")
  end

  it "credits evidence the repository already has rather than asking for it again" do
    baseline = baseline_for({
      "SECURITY.md" => "Mail security@example.com.",
      ".github/workflows/ci.yml" => "jobs:\n  scan:\n    steps:\n      - uses: gitleaks/gitleaks-action@v2\n",
      ".frankenstein.yml" => declaring(:strict)
    })

    expect(baseline.result_for(:"security-policy")).to be_verified
    expect(baseline.result_for(:"security-secret-scanning")).to be_verified
    expect(baseline.unresolved_required.map { |r| r.criterion.id }).to eq([:"security-dependency-review"])
  end

  it "lets an owner accept a missing control as attributable risk instead of faking the evidence" do
    baseline = baseline_for({".frankenstein.yml" => declaring(:local, <<~YAML)})
      waivers:
        - target: security-secret-scanning
          reason: "no third-party scanners on this air-gapped runner; TICKET-7"
          expires: 2999-01-01
    YAML

    secrets = baseline.result_for(:"security-secret-scanning")
    expect(secrets).to be_accepted_risk
    expect(secrets.detail).to include("TICKET-7")
    expect(baseline.state.to_sym).to eq(:alive)
  end

  it "treats a contract naming an unknown control as an error, and an error as unproven" do
    baseline = baseline_for({".frankenstein.yml" => <<~YAML})
      version: 1
      intent: maintain
      profile: generic
      acceptance:
        checks:
          - id: vibes
            claim: "vibes are immaculate"
            evaluator: security_evidence
            target: vibes
            required: true
    YAML

    vibes = baseline.result_for(:vibes)
    expect(vibes.status).to eq(:error)
    expect(vibes.detail).to include("Unknown security control")
    # "We could not tell" is not proof: a broken check must never read green.
    expect(baseline.state.to_sym).to eq(:unproven)
  end
end
