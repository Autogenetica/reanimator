# frozen_string_literal: true

RSpec.describe Frankenstein::Discovery do
  def discover(**kwargs)
    Frankenstein::Discovery.new(make_repository(**kwargs)).run
  end

  describe "a conventional Ruby gem" do
    subject(:result) do
      discover(files: {
        "Gemfile" => "source 'https://rubygems.org'\ngemspec\n",
        "Gemfile.lock" => "GEM\n",
        "widget.gemspec" => "Gem::Specification.new do |s|\n  s.required_ruby_version = '>= 3.1.0'\nend\n",
        ".rspec" => "--require spec_helper\n",
        ".standard.yml" => "ruby_version: 3.1\n",
        "exe/widget" => "#!/usr/bin/env ruby\n"
      })
    end

    it "detects the gem, its commands, and its runtime pin with provenance" do
      expect(result.fact?(:ruby_gem)).to be(true)
      expect(result[:ruby_gem].confidence.to_sym).to eq(:high)
      expect(result[:ruby_gem].provenance.source).to eq("widget.gemspec")

      expect(result.discovered_commands).to include(
        tests: "bundle exec rspec",
        lint: "bundle exec standardrb",
        build: "gem build widget.gemspec"
      )
      expect(Array(result.value(:supported_ruby))).to eq([">= 3.1.0"])
    end

    it "suggests the ruby-cli profile because it ships an executable" do
      expect(result.suggested_profile).to eq(:"ruby-cli")
    end
  end

  describe "a Rails application with CI" do
    subject(:result) do
      discover(files: {
        "Gemfile" => "gem 'rails'\n",
        "config/application.rb" => "module App\n  class Application < Rails::Application\n  end\nend\n",
        "config/deploy.yml" => "service: app\n",
        ".github/workflows/ci.yml" => <<~YAML
          jobs:
            test:
              strategy:
                matrix:
                  ruby: ["3.2", "3.3"]
              steps:
                - uses: actions/dependency-review-action@v4
        YAML
      })
    end

    it "detects Rails, its deployment surface, the CI matrix, and security controls" do
      expect(result.suggested_profile).to eq(:"rails-app")
      expect(result.in_category(:deployment).map(&:key)).to include(:deploy_deploy)
      expect(Array(result.value(:ci_ruby_matrix))).to eq(%w[3.2 3.3])
      expect(result.in_category(:security_controls).map(&:claim).join).to include("Dependency review")
    end
  end

  describe "a fork" do
    it "detects the fork relationship from an upstream remote" do
      result = discover(
        files: {"Gemfile" => "gem 'rails'\n"},
        upstream: "https://github.com/original/project.git"
      )
      expect(result.fact?(:fork_of)).to be(true)
      expect(result[:fork_of].value).to eq("original/project")
    end
  end

  it "never raises when a repository is empty" do
    expect { discover }.not_to raise_error
    expect(discover.facts).to eq([])
  end

  it "survives non-UTF-8 files and still detects the ecosystem" do
    path = make_repo(files: {"widget.gemspec" => "x"})
    # A Gemfile with an invalid byte would otherwise make the detector's regex
    # raise, get swallowed, and silently drop the Bundler fact.
    File.binwrite(File.join(path, "Gemfile"), "ruby \xE2 '3.3.0'\nsource 'x'\n")

    result = Frankenstein::Discovery.new(Frankenstein::Repository.at(path)).run
    expect(result.fact?(:bundler)).to be(true)
  end
end
