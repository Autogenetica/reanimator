# frozen_string_literal: true

# Section 12: a posture that promises deny-by-default egress must either deliver
# it or refuse to execute. These examples pin the three outcomes - enforced,
# refused, and plainly-stated unrestricted - and the places a refusal must not
# be mistaken for a pass.
RSpec.describe Reanimator::EgressControl do
  def posture(name) = Reanimator::SecurityPosture[name]

  describe ".for" do
    it "denies egress through the namespace prefix when the host can enforce it" do
      decision = described_class.for(posture(:strict), namespace: -> { %w[unshare --net] })

      expect(decision).to be_denied
      expect(decision.prefix).to eq(%w[unshare --net])
      expect(decision.reason).to include("network egress denied")
    end

    it "refuses, and says why, when a denying posture cannot be enforced" do
      decision = described_class.for(posture(:local), namespace: -> {})

      expect(decision).to be_refused
      expect(decision.prefix).to be_nil
      expect(decision.reason).to include("local posture requires denied network egress")
    end

    it "leaves balanced unrestricted and says the registry allowlist is advisory" do
      decision = described_class.for(posture(:balanced), namespace: -> { raise "must not probe" })

      expect(decision.mode).to eq(:unrestricted)
      expect(decision.prefix).to eq([])
      expect(decision.reason).to include("allowlist is advisory")
    end

    it "leaves custom unrestricted without inventing a rule" do
      decision = described_class.for(posture(:custom), namespace: -> { raise "must not probe" })

      expect(decision.mode).to eq(:unrestricted)
      expect(decision.reason).to include("declares no egress rule")
    end
  end

  # Needs a host with unprivileged network namespaces, which is the claim being
  # tested: inside the prefix there is nothing but loopback. Elsewhere it shows
  # as pending, so a green run never hides that enforcement went untested.
  describe "real enforcement" do
    it "leaves a command with only the loopback interface" do
      skip "no unprivileged network namespaces on #{RUBY_PLATFORM}" unless described_class.namespace_prefix

      result = Reanimator::BoundedCommand.run(
        "sed -n '3,$p' /proc/net/dev | cut -d: -f1 | tr -d ' '",
        chdir: Dir.pwd, timeout: 10, prefix: described_class.namespace_prefix
      )

      expect(result).to be_success
      expect(result.output.split).to eq(["lo"])
    end
  end

  describe "in a baseline" do
    def contract_for(posture_name, run:)
      root = make_repo(files: {".reanimator.yml" => <<~YAML})
        version: 1
        intent: maintain
        profile: generic
        security:
          posture: #{posture_name}
        acceptance:
          checks:
            - id: suite
              claim: "The suite passes."
              run: #{run.inspect}
              required: true
      YAML
      Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(root)).resolve
    end

    def marker = File.join(make_repo(files: {}), "ran")

    it "refuses to execute under strict when egress cannot be enforced, and runs nothing" do
      allow(described_class).to receive(:namespace_prefix).and_return(nil)
      path = marker
      baseline = Reanimator::BaselineRunner.new(contract_for(:strict, run: "touch #{path}"), execute: true).run

      expect(File.exist?(path)).to be(false)
      expect(baseline.executed?).to be(false)
      expect(baseline.execution_refused?).to be(true)
      expect(baseline.result_for(:suite).status).to eq(:skipped)
      expect(baseline.result_for(:suite).detail).to include("Not run: the strict posture requires denied network egress")
      expect(baseline.state.to_sym).not_to eq(:alive)
    end

    it "says in the report that nothing ran and why" do
      allow(described_class).to receive(:namespace_prefix).and_return(nil)
      baseline = Reanimator::BaselineRunner.new(contract_for(:strict, run: "true"), execute: true).run

      expect(Reanimator::Reports::Baseline.new(baseline).render)
        .to include("Mode:    not executed — the strict posture requires denied network egress")
    end

    it "runs every command through the enforcing prefix when it is available" do
      allow(described_class).to receive(:namespace_prefix).and_return(%w[env REANIMATOR_EGRESS=denied])
      baseline = Reanimator::BaselineRunner.new(
        contract_for(:strict, run: 'test "$REANIMATOR_EGRESS" = denied'), execute: true
      ).run

      expect(baseline.result_for(:suite)).to be_verified
      expect(Reanimator::Reports::Baseline.new(baseline).render).to include("network egress denied")
    end

    it "states plainly that balanced execution is not network-restricted" do
      baseline = Reanimator::BaselineRunner.new(contract_for(:balanced, run: "true"), execute: true).run

      expect(baseline.result_for(:suite)).to be_verified
      expect(Reanimator::Reports::Baseline.new(baseline).render).to include("allowlist is advisory")
    end

    it "never probes the host in the read-only default" do
      expect(described_class).not_to receive(:namespace_prefix)
      baseline = Reanimator::BaselineRunner.new(contract_for(:strict, run: "true")).run

      expect(baseline.result_for(:suite).status).to eq(:planned)
      expect(baseline.execution_refused?).to be(false)
    end
  end

  describe "in a bounded repair" do
    it "stops safely instead of reading a refused baseline as healthy" do
      allow(described_class).to receive(:namespace_prefix).and_return(nil)
      root = make_repo(files: {".reanimator.yml" => <<~YAML})
        version: 1
        intent: maintain
        profile: generic
        security:
          posture: strict
        autonomy:
          repair: allowed
        acceptance:
          checks:
            - id: suite
              run: "false"
              required: true
      YAML
      contract = Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(root)).resolve
      run = Reanimator::RepairRun.new(contract).run

      expect(run.outcome).to eq(:safe_stop)
      expect(run.reason).to include("Repair needs an executed baseline")
      expect(run.reason).to include("cannot enforce")
    end
  end
end
