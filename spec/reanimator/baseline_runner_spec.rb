# frozen_string_literal: true

RSpec.describe Reanimator::BaselineRunner do
  def baseline_for(files, execute: false)
    contract = Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(make_repo(files: files))).resolve
    described_class.new(contract, execute: execute).run
  end

  describe "the read-only default" do
    it "plans command checks without executing them and reports Unproven" do
      baseline = baseline_for({"Gemfile" => "gemspec\n", "widget.gemspec" => "x"})

      expect(baseline.executed?).to be(false)
      expect(baseline.tally).to include(planned: a_value > 0)
      expect(baseline.state.to_sym).to eq(:unproven)
    end

    it "still runs native evaluators, so evidence is graded with no execution" do
      files = {
        "Gemfile" => "gemspec\n",
        "widget.gemspec" => "Gem::Specification.new { |s| s.required_ruby_version = '>= 3.1.0' }\n",
        "README.md" => "# widget"
      }
      baseline = baseline_for(files)
      support = baseline.results.find { |r| r.criterion.id == :support_matrix }
      # support_matrix is native: it grades declared-but-untested Ruby as
      # missing evidence even though nothing executed.
      expect(support.status).to eq(:missing_evidence)
    end
  end

  describe "a preserved artifact" do
    it "is Sleeping once integrity and documentation are proven, without executing anything" do
      root = make_repo(files: {
        "README.md" => "# reproduce me",
        ".reanimator.yml" => "version: 1\nintent: preserve\nprofile: rails-legacy\n"
      }, git: true)
      contract = Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(root)).resolve
      baseline = described_class.new(contract).run

      expect(baseline.executed?).to be(false)
      expect(baseline.state.to_sym).to eq(:sleeping)
      expect(baseline.verified_vitality_rate).to eq(1.0)
    end
  end

  describe "bounded execution" do
    it "verifies a passing required check and reports Alive" do
      files = {
        "README.md" => "# x",
        ".reanimator.yml" => <<~YAML
          version: 1
          intent: maintain
          profile: generic
          acceptance:
            checks:
              - id: ok
                run: "true"
                required: true
        YAML
      }
      baseline = baseline_for(files, execute: true)

      expect(baseline.executed?).to be(true)
      expect(baseline.results.find { |r| r.criterion.id == :ok }).to be_verified
      expect(baseline.state.to_sym).to eq(:alive)
    end

    it "reports At risk when a required check fails" do
      files = {
        ".reanimator.yml" => <<~YAML
          version: 1
          intent: maintain
          profile: generic
          acceptance:
            checks:
              - id: must
                run: "false"
                required: true
        YAML
      }
      baseline = baseline_for(files, execute: true)
      expect(baseline.results.find { |r| r.criterion.id == :must }).to be_failed
      expect(baseline.state.to_sym).to eq(:at_risk)
    end

    it "does not execute when the global allowance is off" do
      Reanimator.configure { |c| c.allow_execution = false }
      files = {
        ".reanimator.yml" => "version: 1\nintent: maintain\nprofile: generic\n" \
          "acceptance:\n  checks:\n    - id: ok\n      run: \"true\"\n      required: true\n"
      }
      baseline = baseline_for(files, execute: true)
      expect(baseline.executed?).to be(false)
      expect(baseline.results.find { |r| r.criterion.id == :ok }.status).to eq(:planned)
    end

    it "runs commands in a disposable copy, leaving the original tree untouched" do
      path = make_repo(files: {
        ".reanimator.yml" => <<~YAML
          version: 1
          intent: maintain
          profile: generic
          acceptance:
            checks:
              - id: writes
                run: "touch sentinel.txt"
                required: true
        YAML
      })
      contract = Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(path)).resolve
      baseline = described_class.new(contract, execute: true).run

      # The command ran (exit 0), but its side effect landed in the throwaway
      # copy - the real working tree never sees sentinel.txt.
      expect(baseline.results.find { |r| r.criterion.id == :writes }).to be_verified
      expect(File.exist?(File.join(path, "sentinel.txt"))).to be(false)
    end
  end
end
