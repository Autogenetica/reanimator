# frozen_string_literal: true

RSpec.describe Reanimator::Discovery do
  def discover(**kwargs)
    Reanimator::Discovery.new(make_repository(**kwargs)).run
  end

  describe "a conventional Ruby gem" do
    subject(:result) do
      root = make_repo(files: {
        "Gemfile" => "source 'https://rubygems.org'\ngemspec\n",
        "Gemfile.lock" => "GEM\n",
        "widget.gemspec" => "Gem::Specification.new do |s|\n  s.required_ruby_version = '>= 3.1.0'\nend\n",
        ".rspec" => "--require spec_helper\n",
        ".standard.yml" => "ruby_version: 3.1\n",
        "exe/widget" => "#!/usr/bin/env ruby\n"
      })
      File.chmod(0o755, File.join(root, "exe/widget"))
      Reanimator::Discovery.new(Reanimator::Repository.at(root)).run
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

    it "offers the shipped executable as the proof that it boots" do
      expect(result.discovered_commands).to include(executable: "bundle exec exe/widget --help")
      expect(result.command_fact(:executable).provenance.source).to eq("exe/widget")
    end
  end

  describe "a gem's shipped executable" do
    # Checkouts carry the executable bit; fixtures have to set it.
    def discover_gem(files, executable: [])
      root = make_repo(files: {"widget.gemspec" => "x"}.merge(files))
      executable.each { |path| File.chmod(0o755, File.join(root, path)) }
      Reanimator::Discovery.new(Reanimator::Repository.at(root)).run
    end

    it "does not offer bin/ developer scripts" do
      result = discover_gem({"bin/console" => "#!/bin/sh\n", "bin/setup" => "#!/bin/sh\n"},
        executable: %w[bin/console bin/setup])
      expect(result.discovered_commands).not_to have_key(:executable)
    end

    it "skips dotfiles and files without the executable bit" do
      result = discover_gem({"exe/.DS_Store" => "x", "exe/README" => "docs", "exe/widget" => "#!/usr/bin/env ruby\n"},
        executable: %w[exe/.DS_Store exe/widget])
      expect(result.discovered_commands[:executable]).to eq("ruby -Ilib exe/widget --help")
    end

    it "shell-escapes a repository-controlled filename" do
      result = discover_gem({"exe/a;touch PWNED;#" => "x"}, executable: ["exe/a;touch PWNED;#"])
      expect(result.discovered_commands[:executable]).to eq("ruby -Ilib exe/a\\;touch\\ PWNED\\;\\# --help")
    end

    it "takes the committed mode over the local filesystem bit in a git checkout" do
      root = make_repo(files: {"widget.gemspec" => "x", "exe/committed" => "x", "exe/local" => "x"})
      File.chmod(0o755, File.join(root, "exe/committed"))
      system("git", "-C", root, "init", "-q", "-b", "main", out: File::NULL)
      system("git", "-C", root, "add", "-A", out: File::NULL)
      system("git", "-C", root, "-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-qm", "f", out: File::NULL)
      File.chmod(0o644, File.join(root, "exe/committed"))
      File.chmod(0o755, File.join(root, "exe/local"))

      result = Reanimator::Discovery.new(Reanimator::Repository.at(root)).run
      expect(result.discovered_commands[:executable]).to eq("ruby -Ilib exe/committed --help")
    end

    def committed_gem(files, modes)
      root = make_repo(files: {"widget.gemspec" => "x"}.merge(files))
      modes.each { |path, mode| File.chmod(mode, File.join(root, path)) }
      system("git", "-C", root, "init", "-q", "-b", "main", out: File::NULL)
      system("git", "-C", root, "add", "-A", out: File::NULL)
      system("git", "-C", root, "-c", "user.email=t@e.com", "-c", "user.name=T", "commit", "-qm", "f", out: File::NULL)
      root
    end

    it "rejects a file committed without the executable bit, whatever the filesystem says" do
      root = committed_gem({"exe/widget" => "x"}, {"exe/widget" => 0o644})
      File.chmod(0o755, File.join(root, "exe/widget"))

      expect(Reanimator::Discovery.new(Reanimator::Repository.at(root)).run.discovered_commands).not_to have_key(:executable)
    end

    it "ignores a directory in exe/, even one holding executables" do
      root = committed_gem({"exe/aaa/tool" => "x", "exe/widget" => "x"}, {"exe/aaa/tool" => 0o755, "exe/widget" => 0o755})

      expect(Reanimator::Discovery.new(Reanimator::Repository.at(root)).run.discovered_commands[:executable])
        .to eq("ruby -Ilib exe/widget --help")
    end

    it "offers the first executable in name order" do
      root = committed_gem({"exe/zeta" => "x", "exe/alpha" => "x"}, {"exe/zeta" => 0o755, "exe/alpha" => 0o755})

      expect(Reanimator::Discovery.new(Reanimator::Repository.at(root)).run.discovered_commands[:executable])
        .to eq("ruby -Ilib exe/alpha --help")
    end

    it "loads the gem through its bundle when there is one" do
      result = discover_gem({"Gemfile" => "gemspec\n", "exe/widget" => "x"}, executable: %w[exe/widget])
      expect(result.discovered_commands[:executable]).to eq("bundle exec exe/widget --help")
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

    result = Reanimator::Discovery.new(Reanimator::Repository.at(path)).run
    expect(result.fact?(:bundler)).to be(true)
  end
end
