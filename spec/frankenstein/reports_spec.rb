# frozen_string_literal: true

RSpec.describe "reports" do
  def baseline(files, **kwargs)
    Frankenstein.baseline(make_repo(files: files, **kwargs))
  end

  describe Frankenstein::Reports::GitHubCheck do
    it "renders the vitality surface and states that nothing changed" do
      out = described_class.new(
        baseline({"README.md" => "# x", ".frankenstein.yml" => "version: 1\nintent: preserve\nprofile: rails-legacy\n"}, git: true)
      ).render

      expect(out).to start_with("FRANKENSTEIN / VITALITY")
      expect(out).to include("SLEEPING")
      expect(out).to include("No source changes were made")
    end

    it "flags attention when required checks are unproven" do
      out = described_class.new(baseline({"Gemfile" => "gemspec\n", "widget.gemspec" => "x"})).render
      expect(out).to include("Attention needed")
    end
  end

  describe Frankenstein::Reports::PortfolioBaseline do
    it "groups repositories by state and closes with the read-only promise" do
      gem = baseline({"Gemfile" => "gemspec\n", "widget.gemspec" => "x"})
      preserved = baseline(
        {"README.md" => "# x", ".frankenstein.yml" => "version: 1\nintent: preserve\nprofile: rails-legacy\n"},
        git: true
      )

      out = described_class.new([gem, preserved], name: "codenamev").render

      expect(out).to include("FRANKENSTEIN BASELINE", "Portfolio: codenamev", "Mode: read-only")
      expect(out).to include("UNPROVEN", "SLEEPING")
      expect(out).to include("NO SOURCE CHANGES WERE MADE", "No coding agent was required.")
    end
  end

  describe Frankenstein::Reports::Inventory do
    it "leads with the recommended set and never preselects everything" do
      portfolio = Frankenstein::Portfolio.new([
        Frankenstein::Portfolio::Entry.new(
          repository: make_repository(files: {"Gemfile" => "gemspec\n", "widget.gemspec" => "x", "lib/w.rb" => "x\n"}),
          classification: Frankenstein::Classifier.new(
            make_repository(files: {"Gemfile" => "gemspec\n", "widget.gemspec" => "x", "lib/w.rb" => "x\n"})
          ).classify
        )
      ])
      out = described_class.new(portfolio).render
      expect(out).to include("Recommended for onboarding:")
    end
  end
end
