# frozen_string_literal: true

RSpec.describe Reanimator::Classifier do
  def classify(**kwargs)
    described_class.new(make_repository(**kwargs)).classify
  end

  it "defaults a fork to upstream observation" do
    result = classify(files: {"README.md" => "# x"}, upstream: "https://github.com/o/p.git")
    expect(result.cohort.key).to eq(:fork_observation)
    expect(result.suggested_intent).to eq(:upstream)
  end

  it "suggests a constrained profile for hardware projects" do
    result = classify(files: {"Gemfile" => "gem 'rpi_gpio'\n"})
    expect(result.cohort.key).to eq(:constrained)
    expect(result.suggested_intent).to eq(:monitor)
  end

  it "treats a README-only repository as a concept to incubate" do
    result = classify(files: {"README.md" => "# just an idea"})
    expect(result.cohort.key).to eq(:readme_only)
  end

  it "recommends an active original for maintenance" do
    result = classify(files: {
      "Gemfile" => "gemspec\n", "widget.gemspec" => "x", "lib/widget.rb" => "module Widget; end\n"
    })
    expect(result.cohort.key).to eq(:active_original)
    expect(result.recommended_for_onboarding?).to be(true)
  end

  it "flags an old unarchived repository as ambiguous rather than maintained" do
    repo = make_repository(files: {"lib/old.rb" => "x\n"}, git: true)
    allow(repo.metadata).to receive(:days_since_activity).and_return(900)
    result = described_class.new(repo).classify
    expect(result.cohort.key).to eq(:old_unarchived)
  end
end
