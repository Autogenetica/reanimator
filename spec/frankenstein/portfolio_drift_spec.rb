# frozen_string_literal: true

GEM_FILES = {
  "README.md" => "# x",
  "Gemfile" => "gemspec\n",
  "widget.gemspec" => "x",
  ".frankenstein.yml" => "version: 1\nintent: maintain\nprofile: ruby-gem\n"
}.freeze

# Section 06 applied to the portfolio of section 04. Drift is only meaningful
# within one repository, so every example here records a portfolio and then
# edits members *in place* rather than comparing lookalike fixtures.
RSpec.describe Frankenstein::PortfolioDrift do
  def widen_autonomy(path)
    File.write(File.join(path, ".frankenstein.yml"),
      "version: 1\nintent: maintain\nprofile: ruby-gem\nautonomy:\n  repair: automatic\n")
  end

  it "sorts a portfolio into what needs a human, what changed harmlessly, and what did not change" do
    widened, renamed, steady = make_portfolio("widened" => GEM_FILES, "renamed" => GEM_FILES, "steady" => GEM_FILES)
    paths = [widened, renamed, steady]
    Frankenstein.portfolio_drift(paths, record: true)

    widen_autonomy(widened)
    File.write(File.join(renamed, ".rspec"), "--color\n")

    drift = Frankenstein.portfolio_drift(paths)

    expect(drift.policy_changed.map(&:name)).to eq(["widened"])
    expect(drift.benign.map(&:name)).to eq(["renamed"])
    expect(drift.unchanged.map(&:name)).to eq(["steady"])
    expect(drift.requires_review?).to be(true)
  end

  it "compares against what was on record when a single pass both records and compares" do
    path = make_portfolio("widget" => GEM_FILES).first
    Frankenstein.portfolio_drift([path], record: true)
    widen_autonomy(path)

    drift = Frankenstein.portfolio_drift([path], record: true)

    # The freshly written snapshot must not be the thing it was compared to.
    expect(drift.policy_changed.map(&:name)).to eq(["widget"])
    expect(drift.entries.first.recorded_to).to end_with(".frankenstein-snapshot.json")
  end

  it "names a repository with nothing recorded, without counting it as fine or as a failure" do
    path = make_portfolio("fresh" => GEM_FILES).first

    drift = Frankenstein.portfolio_drift([path])

    expect(drift.unrecorded.map(&:name)).to eq(["fresh"])
    expect(drift.entries.first).not_to be_failed
    # A first run has nothing to compare against; that is not a reason to fail CI.
    expect(drift.requires_review?).to be(false)
  end

  # Fail closed. "We could not tell" is not "nothing changed", and corrupting a
  # snapshot file must never be a way to make a drift gate pass.
  it "treats a snapshot it cannot read as needing review" do
    path = make_portfolio("broken" => GEM_FILES).first
    File.write(File.join(path, ".frankenstein-snapshot.json"), "not json at all")

    drift = Frankenstein.portfolio_drift([path])

    expect(drift.failed.map(&:name)).to eq(["broken"])
    expect(drift.entries.first.error).to include("not a valid contract snapshot")
    expect(drift.requires_review?).to be(true)
  end

  it "is not stopped by one unreadable member" do
    broken, fine = make_portfolio("broken" => GEM_FILES, "fine" => GEM_FILES)
    Frankenstein.portfolio_drift([broken, fine], record: true)
    File.write(File.join(broken, ".frankenstein-snapshot.json"), "{")

    drift = Frankenstein.portfolio_drift([broken, fine])

    expect(drift.failed.map(&:name)).to eq(["broken"])
    expect(drift.unchanged.map(&:name)).to eq(["fine"])
  end

  describe "snapshots kept portfolio-side" do
    it "records and compares repositories it cannot commit a file into" do
      directory = Dir.mktmpdir("frankenstein-snaps")
      path = make_portfolio("widget" => GEM_FILES).first

      Frankenstein.portfolio_drift([path], snapshots: directory, record: true)
      expect(File.exist?(File.join(path, ".frankenstein-snapshot.json"))).to be(false)

      widen_autonomy(path)
      drift = Frankenstein.portfolio_drift([path], snapshots: directory)

      expect(drift.policy_changed.map(&:name)).to eq(["widget"])
      expect(drift.store.record_command).to include("--snapshots #{directory}")
    end
  end

  it "serializes to a machine-readable triage summary" do
    widened, steady = make_portfolio("widened" => GEM_FILES, "steady" => GEM_FILES)
    Frankenstein.portfolio_drift([widened, steady], record: true)
    widen_autonomy(widened)

    hash = Frankenstein.portfolio_drift([widened, steady], name: "codenamev").to_h

    expect(hash[:portfolio]).to eq("codenamev")
    expect(hash[:requires_review]).to be(true)
    expect(hash[:tally]).to include(policy_changed: 1, unchanged: 1)
    expect(hash[:repositories].map { |r| r[:repository] }).to eq(%w[widened steady])
  end
end
