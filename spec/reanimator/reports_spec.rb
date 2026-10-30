# frozen_string_literal: true

RSpec.describe "reports" do
  def baseline(files, **kwargs)
    Reanimator.baseline(make_repo(files: files, **kwargs))
  end

  describe Reanimator::Reports::GitHubCheck do
    it "renders the vitality surface and states that nothing changed" do
      out = described_class.new(
        baseline({"README.md" => "# x", ".reanimator.yml" => "version: 1\nintent: preserve\nprofile: rails-legacy\n"}, git: true)
      ).render

      expect(out).to start_with("REANIMATOR / VITALITY")
      expect(out).to include("SLEEPING")
      expect(out).to include("No source changes were made")
    end

    it "says planned checks are not yet proven without claiming anyone is needed" do
      out = described_class.new(baseline({"Gemfile" => "gemspec\n", "widget.gemspec" => "x"})).render
      expect(out).to include("Not proven yet")
      expect(out).not_to include("Attention needed")
    end
  end

  describe Reanimator::Reports::PortfolioBaseline do
    it "groups repositories by state and closes with the read-only promise" do
      gem = baseline({"Gemfile" => "gemspec\n", "widget.gemspec" => "x"})
      preserved = baseline(
        {"README.md" => "# x", ".reanimator.yml" => "version: 1\nintent: preserve\nprofile: rails-legacy\n"},
        git: true
      )

      out = described_class.new([gem, preserved], name: "codenamev").render

      expect(out).to include("REANIMATOR BASELINE", "Portfolio: codenamev", "Mode: read-only")
      expect(out).to include("UNPROVEN", "SLEEPING")
      expect(out).to include("NO SOURCE CHANGES WERE MADE", "No coding agent was required.")
    end
  end

  describe Reanimator::Reports::Inventory do
    it "leads with the recommended set and never preselects everything" do
      portfolio = Reanimator::Portfolio.new([
        Reanimator::Portfolio::Entry.new(
          repository: make_repository(files: {"Gemfile" => "gemspec\n", "widget.gemspec" => "x", "lib/w.rb" => "x\n"}),
          classification: Reanimator::Classifier.new(
            make_repository(files: {"Gemfile" => "gemspec\n", "widget.gemspec" => "x", "lib/w.rb" => "x\n"})
          ).classify
        )
      ])
      out = described_class.new(portfolio).render
      expect(out).to include("Recommended for onboarding:")
    end
  end

  # Section 12: the posture is part of onboarding, not a hidden settings page,
  # so the contract has to say in words what it makes binding.
  describe Reanimator::Reports::Contract do
    it "names the posture, explains it, and lists exactly what it requires" do
      path = make_repo(files: {
        "README.md" => "# widget",
        ".reanimator.yml" => "version: 1\nintent: maintain\nprofile: generic\nsecurity:\n  posture: strict\n"
      })
      contract = Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(path)).resolve

      out = described_class.new(contract).render

      expect(out).to include("Security posture: strict")
      expect(out).to include("deny-by-default network and secrets")
      expect(out).to include("Required: security policy, dependency review, secret scanning")
      expect(out).to include("Advisory: static analysis, ownership")
    end

    it "says plainly when a posture requires nothing, rather than leaving the line blank" do
      path = make_repo(files: {".reanimator.yml" => "version: 1\nintent: maintain\nprofile: generic\n"})
      contract = Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(path)).resolve

      expect(described_class.new(contract).render).to include("Required: none")
    end
  end
end

RSpec.describe "drift reporting" do
  def snapshot_for(files)
    contract = Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(make_repo(files: files))).resolve
    Reanimator::ContractSnapshot.of(contract)
  end

  let(:declared) do
    {".reanimator.yml" => <<~YAML}
      version: 1
      intent: maintain
      profile: generic
      acceptance:
        checks:
          - id: tests
            claim: "the suite passes"
            run: "bundle exec rspec"
            required: true
    YAML
  end

  # `--format text` used to print JSON whenever there was no --since, which
  # contradicted its own flag and greeted a new user with a wall of braces.
  it "describes what a repository is required to prove, in prose" do
    rendered = Reanimator::Reports::Snapshot.new(snapshot_for(declared)).render

    expect(rendered).to include("Contract snapshot —")
    expect(rendered).to match(/Proves:\s+\d+ criteri/)
    expect(rendered).to include("Record this with `reanimator drift --record`")
    expect(rendered).not_to include("{")
  end

  it "names the file it was recorded to, and how to compare against it" do
    rendered = Reanimator::Reports::Snapshot.new(snapshot_for(declared), saved_to: "snap.json").render

    expect(rendered).to include("Recorded to snap.json")
    expect(rendered).to include("Compare later with: reanimator drift")
  end

  it "reads the same whether the snapshot is fresh or loaded from disk" do
    fresh = snapshot_for(declared)
    loaded = Reanimator::ContractSnapshot.from_h(JSON.parse(fresh.to_json))

    taken = ->(s) { Reanimator::Reports::Snapshot.new(s).render.lines[1] }
    expect(taken.call(loaded)).to eq(taken.call(fresh))
  end

  # A maintainer whose build just went red is looking at this output and
  # nowhere else, so it has to say how to accept drift they meant.
  it "tells a maintainer how to accept drift they intended" do
    path = make_repo(files: declared)
    resolve = -> { Reanimator::ContractSnapshot.of(Reanimator::EffectivePolicyResolver.new(Reanimator::Repository.at(path)).resolve) }

    before = resolve.call
    File.write(File.join(path, ".reanimator.yml"), declared[".reanimator.yml"].sub("required: true", "required: false"))
    report = Reanimator::DriftDetector.between(before, resolve.call)

    rendered = Reanimator::Reports::Drift.new(report, record_with: "reanimator drift --save snap.json").render
    expect(rendered).to include("REVIEW REQUIRED")
    expect(rendered).to include("reanimator drift --save snap.json")
  end
end

PF_FILES = {
  "README.md" => "# x",
  "Gemfile" => "gemspec\n",
  "widget.gemspec" => "x",
  ".reanimator.yml" => "version: 1\nintent: maintain\nprofile: ruby-gem\n"
}.freeze

RSpec.describe Reanimator::Reports::PortfolioDrift do
  def rendered(paths, **kwargs)
    described_class.new(Reanimator.portfolio_drift(paths, **kwargs)).render
  end

  it "leads with the repositories that need a human and says why each change matters" do
    widened, renamed, steady = make_portfolio("widened" => PF_FILES, "renamed" => PF_FILES, "steady" => PF_FILES)
    paths = [widened, renamed, steady]
    Reanimator.portfolio_drift(paths, record: true)
    File.write(File.join(widened, ".reanimator.yml"),
      "version: 1\nintent: maintain\nprofile: ruby-gem\nautonomy:\n  repair: automatic\n")
    File.write(File.join(renamed, ".rspec"), "--color\n")

    out = rendered(paths)

    expect(out.index("REVIEW REQUIRED — 1 repository")).to be < out.index("CHANGED, BENIGN")
    expect(out).to include("Autonomy was widened")
    expect(out).to include("UNCHANGED — 1 repository")
    expect(out).to include("Intended? Re-record with: reanimator drift --record")
  end

  it "says plainly that nothing needs a decision when nothing drifted" do
    paths = make_portfolio("steady" => PF_FILES)
    Reanimator.portfolio_drift(paths, record: true)

    expect(rendered(paths)).to include("nothing here needs a decision")
  end

  # The read-only promise, stated precisely rather than generously: recording
  # writes snapshot files, so the footer says which it actually did.
  it "distinguishes writing nothing from writing snapshots" do
    paths = make_portfolio("widget" => PF_FILES)

    expect(rendered(paths)).to include("NO FILES WERE WRITTEN. NO SOURCE CHANGES WERE MADE.")
    expect(rendered(paths, record: true)).to include("Recorded 1 snapshot. NO SOURCE CHANGES WERE MADE.")
  end

  it "calls an unreadable snapshot out as review required, not as a quiet pass" do
    paths = make_portfolio("broken" => PF_FILES)
    File.write(File.join(paths.first, ".reanimator-snapshot.json"), "not json")

    out = rendered(paths)

    expect(out).to include("COULD NOT READ — 1 repository")
    expect(out).to include("so drift could not be ruled out there")
  end
end
