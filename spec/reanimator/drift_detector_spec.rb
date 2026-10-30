# frozen_string_literal: true

BASE_SNAPSHOT = {
  repository: "codenamev/widget",
  intent: :maintain,
  profile: :"ruby-gem",
  security_posture: :balanced,
  autonomy: {observe: :automatic, diagnose: :automatic, repair: :disabled},
  protected_paths: [".reanimator.yml", ".github/workflows/**"],
  criteria: [
    {id: :tests, evaluator: :command, run: "bundle exec rspec", required: true},
    {id: :docs, evaluator: :documentation, run: nil, required: false}
  ],
  waivers: [],
  support_matrix: %w[3.2 3.3],
  security_controls: [:dependabot, :secret_scanning]
}.freeze

RSpec.describe Reanimator::DriftDetector do
  def snapshot(**overrides)
    Reanimator::ContractSnapshot.new(**BASE_SNAPSHOT, **overrides)
  end

  # Drift between an unchanged contract and itself is silence, not a report
  # with nothing in it that still demands attention.
  def drift(**overrides)
    described_class.between(snapshot, snapshot(**overrides))
  end

  def subjects(changes) = changes.map(&:subject)

  it "reports no drift when nothing changed" do
    report = drift
    expect(report).not_to be_drifted
    expect(report.requires_review?).to be(false)
    expect(report.changes).to be_empty
  end

  describe "policy changes - less is proven than before" do
    it "flags a lifecycle intent change" do
      report = drift(intent: :retire)
      expect(subjects(report.policy_changes)).to eq(["intent"])
      expect(report.policy_changes.first.summary).to eq("intent: maintain → retire")
      expect(report.requires_review?).to be(true)
    end

    it "flags a profile or security posture change" do
      expect(subjects(drift(profile: :generic).policy_changes)).to eq(["profile"])
      expect(subjects(drift(security_posture: :permissive).policy_changes)).to eq(["security posture"])
    end

    it "flags a widened autonomy grant" do
      report = drift(autonomy: BASE_SNAPSHOT[:autonomy].merge(repair: :automatic))
      expect(subjects(report.policy_changes)).to eq(["autonomy repair"])
      expect(report.policy_changes.first.explanation).to match(/widened/)
    end

    it "flags a protected path that lost its elevated review" do
      report = drift(protected_paths: [".reanimator.yml"])
      expect(report.policy_changes.first.summary).to eq("protected path removed: .github/workflows/**")
    end

    # The specification's own example: a narrowed runtime matrix.
    it "flags a narrowed runtime matrix" do
      report = drift(support_matrix: %w[3.3])
      expect(report.policy_changes.first.summary).to eq("supported runtime removed: 3.2")
      expect(report.policy_changes.first.explanation).to match(/narrowed/)
    end

    # And the other: a removed security gate.
    it "flags a removed security control" do
      report = drift(security_controls: [:dependabot])
      expect(report.policy_changes.first.summary).to eq("security control removed: secret_scanning")
    end

    it "flags a dropped required criterion" do
      report = drift(criteria: [BASE_SNAPSHOT[:criteria].last])
      expect(report.policy_changes.first.summary).to eq("criterion removed: tests")
    end

    it "flags a required criterion quietly becoming optional" do
      relaxed = [BASE_SNAPSHOT[:criteria].first.merge(required: false), BASE_SNAPSHOT[:criteria].last]
      report = drift(criteria: relaxed)
      expect(report.policy_changes.first.summary).to eq("criterion tests required: true → false")
    end

    it "flags a changed evaluator, since the old and new evidence are not comparable" do
      swapped = [BASE_SNAPSHOT[:criteria].first.merge(evaluator: :http_smoke), BASE_SNAPSHOT[:criteria].last]
      report = drift(criteria: swapped)
      expect(report.policy_changes.first.summary).to eq("criterion tests evaluator: command → http_smoke")
    end

    it "flags a new waiver and an extended one" do
      added = described_class.between(snapshot, snapshot(waivers: [{target: :tests, expires: nil}]))
      expect(added.policy_changes.first.summary).to eq("waiver added: tests")

      before = snapshot(waivers: [{target: :tests, expires: "2030-01-01T00:00:00Z"}])
      after = snapshot(waivers: [{target: :tests, expires: "2031-01-01T00:00:00Z"}])
      extended = described_class.between(before, after)
      expect(extended.policy_changes.first.subject).to eq("waiver tests expiry")
      expect(extended.policy_changes.first.explanation).to match(/extended/)
    end

    # Every other judgement here fails closed. An expiry nobody can parse is
    # not evidence that the accepted risk got smaller, so it must not be filed
    # under "nobody needs to look".
    it "flags a waiver whose new expiry cannot be read, rather than assuming it shrank" do
      before = snapshot(waivers: [{target: :tests, expires: "2030-01-01T00:00:00Z"}])
      after = snapshot(waivers: [{target: :tests, expires: "whenever we get to it"}])
      report = described_class.between(before, after)

      expect(report.requires_review?).to be(true)
      expect(report.policy_changes.first.explanation).to match(/cannot be read/)
    end

    it "treats an open-ended waiver as outliving every dated one" do
      before = snapshot(waivers: [{target: :tests, expires: "2030-01-01T00:00:00Z"}])
      after = snapshot(waivers: [{target: :tests, expires: nil}])
      report = described_class.between(before, after)

      expect(report.requires_review?).to be(true)
      expect(report.policy_changes.first.to).to eq("open-ended")
    end
  end

  describe "benign changes - reported, but nobody is interrupted" do
    # The specification's example of drift that is not alarming.
    it "treats a renamed test command as benign" do
      renamed = [BASE_SNAPSHOT[:criteria].first.merge(run: "bin/rspec"), BASE_SNAPSHOT[:criteria].last]
      report = drift(criteria: renamed)

      expect(report).to be_drifted
      expect(report.requires_review?).to be(false)
      expect(report.benign_changes.first.summary).to eq("criterion tests command: bundle exec rspec → bin/rspec")
    end

    it "treats added checks, added protection, and a widened matrix as benign" do
      added = drift(criteria: BASE_SNAPSHOT[:criteria] + [{id: :build, evaluator: :command, run: "gem build", required: true}])
      expect(added.benign_changes.first.summary).to eq("criterion added: build")

      protection = drift(protected_paths: BASE_SNAPSHOT[:protected_paths] + ["config/**"])
      expect(protection.benign_changes.first.summary).to eq("protected path added: config/**")

      widened = drift(support_matrix: %w[3.2 3.3 3.4])
      expect(widened.benign_changes.first.summary).to eq("supported runtime added: 3.4")

      expect([added, protection, widened]).to all(satisfy { |report| !report.requires_review? })
    end

    it "treats narrowed autonomy and a withdrawn waiver as benign" do
      narrowed = drift(autonomy: BASE_SNAPSHOT[:autonomy].merge(diagnose: :disabled))
      expect(narrowed.benign_changes.first.explanation).to match(/narrowed/)

      withdrawn = described_class.between(snapshot(waivers: [{target: :tests, expires: nil}]), snapshot)
      expect(withdrawn.benign_changes.first.summary).to eq("waiver removed: tests")
      expect(withdrawn.requires_review?).to be(false)
    end

    it "treats a dropped optional check as benign" do
      report = drift(criteria: [BASE_SNAPSHOT[:criteria].first])
      expect(report.benign_changes.first.summary).to eq("criterion removed: docs")
      expect(report.requires_review?).to be(false)
    end
  end

  it "keeps a policy change visible even when benign changes outnumber it" do
    report = drift(
      support_matrix: %w[3.3],
      protected_paths: BASE_SNAPSHOT[:protected_paths] + ["config/**", "db/**"],
      criteria: [BASE_SNAPSHOT[:criteria].first.merge(run: "bin/rspec"), BASE_SNAPSHOT[:criteria].last]
    )

    expect(report.requires_review?).to be(true)
    expect(report.policy_changes.size).to eq(1)
    expect(report.benign_changes.size).to eq(3)
  end

  it "treats a command that disappears as lost proof, not a rename" do
    criteria = ->(run) { [{id: :exe, evaluator: :command, run: run, required: false}] }

    lost = described_class.between(snapshot(criteria: criteria.call("bin/x --help")), snapshot(criteria: criteria.call(nil)))
    gained = described_class.between(snapshot(criteria: criteria.call(nil)), snapshot(criteria: criteria.call("bin/x --help")))

    expect(lost).to be_requires_review
    expect(gained).not_to be_requires_review
  end

  it "refuses to compare two different repositories" do
    expect { described_class.between(snapshot, snapshot(repository: "codenamev/other")) }
      .to raise_error(Reanimator::ContractError, /only meaningful within one repository/)
  end

  # Two local checkouts can share a directory name, and matching on the name
  # alone answered "no drift" - the most dangerous possible answer, since it
  # reports a repository unchanged that was never recorded. A git origin names
  # a repository exactly, so it decides whenever both snapshots carry one.
  it "recognises one repository whether it was cloned over SSH or HTTPS" do
    recorded = snapshot(origin: "git@github.com:Autogenetica/reanimator.git")
    current = snapshot(origin: "https://github.com/Autogenetica/reanimator")

    expect { described_class.between(recorded, current) }.not_to raise_error
  end

  it "refuses two repositories that share a name but not an origin" do
    recorded = snapshot(origin: "git@github.com:codenamev/widget.git")
    current = snapshot(origin: "git@github.com:someone-else/widget.git")

    expect { described_class.between(recorded, current) }
      .to raise_error(Reanimator::ContractError,
        "Snapshot is for git@github.com:codenamev/widget.git, not git@github.com:someone-else/widget.git; " \
        "drift is only meaningful within one repository.")
  end

  it "compares by origin even when the recorded names differ" do
    recorded = snapshot(repository: "widget", origin: "git@github.com:codenamev/widget.git")
    current = snapshot(repository: "codenamev/widget", origin: "git@github.com:codenamev/widget.git")

    expect { described_class.between(recorded, current) }.not_to raise_error
  end

  it "serializes with the two kinds kept apart" do
    hash = drift(intent: :retire, support_matrix: %w[3.2 3.3 3.4]).to_h

    expect(hash[:requires_review]).to be(true)
    expect(hash[:policy_changes].map { |c| c[:subject] }).to eq(["intent"])
    expect(hash[:benign_changes].map { |c| c[:subject] }).to eq(["supported runtime"])
  end
end
