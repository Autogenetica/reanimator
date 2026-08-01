# frozen_string_literal: true

require "thor"
require "json"

module Frankenstein
  # The interactive surface. Every command here is read-only by default and
  # maps to one onboarding stage from section 03: inventory (classify),
  # discover, contract (review), and baseline (measure). Nothing in this CLI
  # writes to a repository or connects an agent - it exists to make the
  # repository's definition of life visible, executable, and trustworthy.
  class CLI < Thor
    def self.exit_on_failure? = true

    desc "version", "Print the Frankenstein version"
    def version
      puts Frankenstein::VERSION
    end
    map %w[--version -v] => :version

    desc "inventory [PATH...]", "Classify repositories into lifecycle cohorts (read-only)"
    long_desc <<~DESC
      Stage 1 of onboarding: classify before acting. Groups each repository into
      a suggested cohort and lifecycle intent, and recommends a small,
      high-confidence set for onboarding - never all of them.
    DESC
    def inventory(*paths)
      guard do
        paths = [Dir.pwd] if paths.empty?
        puts Reports::Inventory.new(Frankenstein.inventory(paths)).render
      end
    end

    desc "discover [PATH]", "Show discovered facts and their provenance (read-only)"
    def discover(path = Dir.pwd)
      guard { puts Reports::Discovery.new(Frankenstein.discover(path)).render }
    end

    desc "contract [PATH]", "Show or export the effective vitality contract"
    option :intent, desc: "Override the inferred lifecycle intent (e.g. maintain, preserve)"
    option :export, type: :boolean, default: false, desc: "Print a minimal .frankenstein.yml instead of the review"
    def contract(path = Dir.pwd)
      guard do
        contract = Frankenstein.contract(path, intent: options[:intent]&.to_sym)
        if options[:export]
          puts ContractFile.dump(contract.to_minimal_hash)
        else
          puts Reports::Contract.new(contract).render
        end
      end
    end

    desc "baseline [PATH]", "Measure a read-only proof-of-life baseline"
    long_desc <<~DESC
      Runs the effective contract's acceptance criteria and reports a
      proof-of-life state. Native checks (integrity, documentation, support
      matrix) always run; command and boot checks only plan unless --execute is
      given, and even then execution is bounded and never edits source.
    DESC
    option :execute, type: :boolean, default: false, desc: "Actually run discovered checks (bounded, read-only)"
    option :intent, desc: "Override the inferred lifecycle intent"
    option :format, default: "text", enum: %w[text check json], desc: "Output format"
    def baseline(path = Dir.pwd)
      guard do
        baseline = Frankenstein.baseline(path, execute: options[:execute], intent: options[:intent]&.to_sym)
        puts render_baseline(baseline, options[:format])
      end
    end

    desc "portfolio [PATH...]", "Baseline several repositories into one report (Appendix A)"
    option :execute, type: :boolean, default: false, desc: "Actually run discovered checks (bounded, read-only)"
    option :name, default: "portfolio", desc: "Portfolio name shown in the report header"
    def portfolio(*paths)
      guard do
        paths = [Dir.pwd] if paths.empty?
        baselines = paths.filter_map do |path|
          Frankenstein.baseline(path, execute: options[:execute])
        rescue RepositoryError => e
          warn "skipping #{path}: #{e.message}"
          nil
        end
        puts Reports::PortfolioBaseline.new(baselines, name: options[:name]).render
      end
    end

    desc "agents", "List coding-agent providers and whether each is available"
    def agents
      guard { puts Reports::Agents.new(Frankenstein.adapters).render }
    end

    desc "commission", "Prove a coding agent is ready via a synthetic repair (no repository writes)"
    long_desc <<~DESC
      Stage 5 of onboarding. Runs the commissioning test from section 08: a
      synthetic repair against a disposable fixture, graded independently by
      Frankenstein's own evaluators. The default local agent always runs; hosted
      providers report themselves unavailable until connected.
    DESC
    option :provider, default: "local", desc: "Provider to commission (local, codex, claude, amp)"
    def commission
      guard do
        report = Frankenstein.commission(provider: options[:provider].to_sym)
        puts Reports::Commissioning.new(report).render
        exit 1 unless report.ready? || report.readiness == :unavailable
      end
    end

    desc "permissions [PATH]", "Show resolved autonomy per task class for a repository"
    option :intent, desc: "Override the inferred lifecycle intent"
    def permissions(path = Dir.pwd)
      guard do
        contract = Frankenstein.contract(path, intent: options[:intent]&.to_sym)
        puts Reports::Permissions.new(contract).render
      end
    end

    private

    def render_baseline(baseline, format)
      case format
      when "check" then Reports::GitHubCheck.new(baseline).render
      when "json" then JSON.pretty_generate(baseline.to_h)
      else Reports::Baseline.new(baseline).render
      end
    end

    # Turns library errors into a clean, single-line CLI failure instead of a
    # backtrace - the tool is for maintainers, not for reading stack traces.
    def guard
      yield
    rescue Frankenstein::Error => e
      warn "frankenstein: #{e.message}"
      exit 1
    end
  end
end
