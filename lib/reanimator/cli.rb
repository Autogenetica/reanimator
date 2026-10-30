# frozen_string_literal: true

require "thor"
require "json"

module Reanimator
  # The interactive surface. Every command here is read-only by default and
  # maps to one onboarding stage from section 03: inventory (classify),
  # discover, contract (review), and baseline (measure). Nothing in this CLI
  # writes to a repository or connects an agent - it exists to make the
  # repository's definition of life visible, executable, and trustworthy.
  #
  # Exit status separates the tool from the repository: 1 means Reanimator
  # itself could not do its job (or drift needs review); 2 means it did its job
  # and a human is needed (section 16 escalation). Inside GitHub Actions the
  # same escalations are also published as annotations and a job summary.
  class CLI < Thor
    EXIT_ERROR = 1
    EXIT_ATTENTION = 2
    # The report each kind of subject contributes to the CI job summary.
    SUMMARY_REPORTS = {Baseline => Reports::GitHubCheck, Run => Reports::Run}.freeze

    def self.exit_on_failure? = true

    desc "version", "Print the Reanimator version"
    def version
      puts Reanimator::VERSION
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
        puts Reports::Inventory.new(Reanimator.inventory(paths)).render
      end
    end

    desc "discover [PATH]", "Show discovered facts and their provenance (read-only)"
    def discover(path = Dir.pwd)
      guard { puts Reports::Discovery.new(Reanimator.discover(path)).render }
    end

    desc "contract [PATH]", "Show or export the effective vitality contract"
    option :intent, desc: "Override the inferred lifecycle intent (e.g. maintain, preserve)"
    option :export, type: :boolean, default: false, desc: "Print a minimal .reanimator.yml instead of the review"
    def contract(path = Dir.pwd)
      guard do
        contract = Reanimator.contract(path, intent: options[:intent]&.to_sym)
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

      Exits 2 when a required criterion needs a human - failed, or unproven for
      any reason other than not being asked to execute. Inside GitHub Actions
      each such criterion is annotated and the check is added to the job summary.
    DESC
    option :execute, type: :boolean, default: false, desc: "Actually run discovered checks (bounded, read-only)"
    option :intent, desc: "Override the inferred lifecycle intent"
    option :format, default: "text", enum: %w[text check json], desc: "Output format"
    def baseline(path = Dir.pwd)
      guard do
        baseline = Reanimator.baseline(path, execute: options[:execute], intent: options[:intent]&.to_sym)
        json = options[:format] == "json"
        emit(render_baseline(baseline, options[:format]), machine: json)
        exit_for([baseline], annotate: !json)
      end
    end

    desc "portfolio [PATH...]", "Baseline several repositories into one report (Appendix A)"
    option :execute, type: :boolean, default: false, desc: "Actually run discovered checks (bounded, read-only)"
    option :name, default: "portfolio", desc: "Portfolio name shown in the report header"
    def portfolio(*paths)
      guard do
        paths = [Dir.pwd] if paths.empty?
        unreadable = []
        baselines = paths.filter_map do |path|
          Reanimator.baseline(path, execute: options[:execute])
        rescue RepositoryError => e
          warn "skipping #{path}: #{e.message}"
          unreadable << path
          nil
        end
        emit(Reports::PortfolioBaseline.new(baselines, name: options[:name]).render)
        exit_for(baselines, bad_input: unreadable.any?)
      end
    end

    desc "agents", "List coding-agent providers and whether each is available"
    def agents
      guard { puts Reports::Agents.new(Reanimator.adapters).render }
    end

    desc "commission", "Prove a coding agent is ready via a synthetic repair (no repository writes)"
    long_desc <<~DESC
      Stage 5 of onboarding. Runs the commissioning test from section 08: a
      synthetic repair against a disposable fixture, graded independently by
      Reanimator's own evaluators. The default local agent always runs; hosted
      providers report themselves unavailable until connected.
    DESC
    option :provider, default: "local", desc: "Provider to commission (local, codex, claude, amp)"
    def commission
      guard do
        report = Reanimator.commission(provider: options[:provider].to_sym)
        puts Reports::Commissioning.new(report).render
        exit EXIT_ERROR unless report.ready? || report.readiness == :unavailable
      end
    end

    desc "repair [PATH]", "Attempt a bounded repair and propose a draft PR (no repository writes)"
    long_desc <<~DESC
      Stage toward bounded stewardship (section 11 repair rung). Finds the first
      failing required criterion, checks the permission model, routes to a ready
      agent, and lets it propose a patch in an isolated workspace. The patch is
      applied only to a separate clean copy and re-verified independently; on
      success a draft PR is materialized but NOT submitted. Nothing is written to
      the repository.
    DESC
    option :provider, default: "local", desc: "Provider to use (local, codex, claude, amp)"
    option :task_class, default: "patch_dependency", desc: "Task class governing autonomy"
    def repair(path = Dir.pwd)
      guard do
        run = Reanimator.repair(path, provider: options[:provider].to_sym, task_class: options[:task_class].to_sym)
        emit(Reports::Run.new(run).render)
        exit_for([run])
      end
    end

    desc "drift [PATH...]", "Record contract snapshots, or detect drift against them"
    long_desc <<~DESC
      Section 06. Configuration drift is the difference between the contract a
      repository resolved to when it was last recorded and the one its evidence
      resolves to now. Differences are separated into policy changes - less is
      being proven than before, so a human should look - and benign ones, such
      as a renamed test command. The exit status is non-zero only for a policy
      change, so CI can gate on it.

      A repository's snapshot normally lives in the repository, committed as
      .reanimator-snapshot.json, so a policy change arrives as a diff in a
      pull request rather than as state hidden in a tool; --record writes it
      there. For repositories you cannot commit a file into, --snapshots DIR
      keeps them side by side, keyed by repository. Pass several paths for a
      portfolio triage list. With nothing recorded yet, shows what the
      repository is currently required to prove. The only files Reanimator
      ever writes are those snapshots, and only when asked.
    DESC
    option :since, desc: "Path to a recorded snapshot to compare against (one repository)"
    option :save, desc: "Path to write the current snapshot to (one repository)"
    option :snapshots, desc: "Directory of recorded snapshots, keyed by repository"
    option :record, type: :boolean, default: false, desc: "Record each current snapshot where it belongs"
    option :intent, desc: "Override the inferred lifecycle intent"
    option :format, default: "text", enum: %w[text json], desc: "Output format"
    def drift(*paths)
      guard do
        paths = [Dir.pwd] if paths.empty?
        (paths.size > 1) ? portfolio_drift(paths) : single_drift(paths.first)
      end
    end

    desc "permissions [PATH]", "Show resolved autonomy per task class for a repository"
    option :intent, desc: "Override the inferred lifecycle intent"
    def permissions(path = Dir.pwd)
      guard do
        contract = Reanimator.contract(path, intent: options[:intent]&.to_sym)
        puts Reports::Permissions.new(contract).render
      end
    end

    desc "families [PATH...]", "Show the compatibility graph: repositories that must stay alive together"
    long_desc <<~DESC
      Section 10. Groups related repositories into families from their structure -
      a project and its examples, deployment samples, docs, or plugins - and shows
      the typed edge between each pair plus the gate that proves it.
    DESC
    def families(*paths)
      guard do
        paths = [Dir.pwd] if paths.empty?
        puts Reports::Families.new(Reanimator.families(paths)).render
      end
    end

    desc "gates [PATH...]", "Evaluate cross-repository family gates (read-only)"
    long_desc <<~DESC
      Proves each family edge by running the downstream member's own check. A
      candidate change upstream can trigger these downstream checks without
      opening anything downstream: with --execute each check runs bounded, in a
      disposable copy, never in the downstream working tree. A failure names the
      exact edge that broke.
    DESC
    option :family, desc: "Limit to one family id"
    option :execute, type: :boolean, default: false, desc: "Actually run downstream checks (bounded, read-only)"
    def gates(*paths)
      guard do
        paths = [Dir.pwd] if paths.empty?
        evaluated = Reanimator.family_gates(paths, family: options[:family], execute: options[:execute])
        if evaluated.empty?
          puts "No repository families detected."
        else
          puts evaluated.map { |family, results| Reports::FamilyGates.new(family, results).render }.join("\n\n")
        end
      end
    end

    private

    # Prints command output. Machine output (JSON) goes out untouched: JSON
    # escapes newlines, so repository text cannot start a workflow command in
    # it, and wrapping it would break it. Reports go through the Actions guard.
    def emit(text, machine: false)
      machine ? puts(text) : ActionsSurface.print_report(text)
    end

    # Publishes the subjects' findings to CI, then exits: EXIT_ERROR when some
    # input could not be read at all ("we could not tell" is never a pass),
    # EXIT_ATTENTION when a finding blocks, normally otherwise.
    #
    # @param subjects [Array<Baseline, Run>]
    # @param annotate [Boolean] false when stdout carries machine output
    # @param bad_input [Boolean] whether some requested input was unreadable
    def exit_for(subjects, annotate: true, bad_input: false)
      findings = subjects.flat_map(&:findings)
      ActionsSurface.publish(
        annotations: annotate ? Reports::Annotations.new(findings).render : [],
        summaries: subjects.map { |s| ["Reanimator — #{s.repository.full_name}", SUMMARY_REPORTS.fetch(s.class).new(s).render] }
      )
      exit EXIT_ERROR if bad_input
      exit EXIT_ATTENTION if findings.any?(&:blocking?)
    end

    # Several paths: a triage list across the portfolio, not one verdict.
    def portfolio_drift(paths)
      %w[since save].each do |single|
        next unless options[single]

        raise ContractError,
          "--#{single} names one file, so it cannot be used with several repositories; use --snapshots DIR."
      end

      drift = Reanimator.portfolio_drift(
        paths, snapshots: options[:snapshots], record: options[:record], intent: options[:intent]&.to_sym
      )
      puts((options[:format] == "json") ? JSON.pretty_generate(drift.to_h) : Reports::PortfolioDrift.new(drift).render)
      exit EXIT_ERROR if drift.requires_review?
    end

    def single_drift(path)
      store = SnapshotStore.new(directory: options[:snapshots])
      repository = Repository.at(path)
      snapshot = Reanimator.snapshot(path, intent: options[:intent]&.to_sym)
      previous = options[:since] ? ContractSnapshot.load(options[:since]) : store.load(repository)
      report = previous && DriftDetector.between(previous, snapshot)

      recorded_to = record_snapshot(snapshot, repository, store)
      puts render_drift(report, snapshot, recorded_to, store)
      exit EXIT_ERROR if report&.requires_review?
    end

    # A snapshot is written only where the maintainer asked for it: --save names
    # an exact file, --record puts it where the store says it belongs. Nothing
    # is written without one of them - detecting drift is not licence to start
    # writing files.
    def record_snapshot(snapshot, repository, store)
      return unless options[:save] || options[:record]

      written = options[:save] ? save_snapshot(snapshot, options[:save]) : store.save(snapshot, repository)
      warn "Recorded contract snapshot for #{snapshot.repository} → #{written}"
      written
    end

    def render_drift(report, snapshot, recorded_to, store)
      return JSON.pretty_generate(report ? report.to_h : snapshot.to_h) if options[:format] == "json"
      return Reports::Drift.new(report, record_with: store.record_command(options[:since])).render if report

      Reports::Snapshot.new(snapshot, saved_to: recorded_to, record_with: store.record_command).render
    end

    def save_snapshot(snapshot, destination)
      File.write(destination, snapshot.to_json)
      destination
    rescue SystemCallError => e
      raise ContractError, "Could not write the contract snapshot to #{destination}: #{e.message}"
    end

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
    rescue Reanimator::Error => e
      warn "reanimator: #{e.message}"
      exit EXIT_ERROR
    end
  end
end
