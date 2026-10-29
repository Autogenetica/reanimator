# frozen_string_literal: true

require "logger"
require "zeitwerk"

# Zeitwerk is the single code loader for the gem: every constant under
# Reanimator:: is autoloaded on first reference, including the CLI, so a
# library consumer (or a future GitHub App host) never pays for Thor or the
# tty-* UI stack at require time. Files must not require_relative their
# siblings - reference the constant and let the loader resolve it.
loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "github_actions" => "GitHubActions",
  "github_check" => "GitHubCheck",
  "github_client" => "GitHubClient"
)
# errors.rb intentionally defines the whole error family in one file, so it is
# required directly rather than autoloaded one-constant-per-file.
loader.ignore("#{__dir__}/reanimator/errors.rb")
# The interactive surface is loaded on demand (exe/reanimator), never eager.
loader.do_not_eager_load("#{__dir__}/reanimator/cli.rb")
loader.setup

require_relative "reanimator/errors"

# Reanimator turns repository intent into a verified, low-friction
# stewardship contract. The public promise, echoed throughout this library, is
# that the first successful run proves something useful *without changing a
# single line of code*: it observes, discovers, resolves an effective
# contract, and measures a read-only baseline before any coding agent or write
# permission is involved.
#
# The module methods below are the "80% path" - a maintainer can go from a
# path on disk to a proof-of-life report in one call.
module Reanimator
  class << self
    attr_writer :configuration
    attr_accessor :logger
  end

  # Quiet by default. The CLI raises verbosity for interactive use; library
  # consumers opt in via Reanimator.logger.level=.
  self.logger ||= Logger.new($stdout, level: Logger::WARN)

  # @return [Configuration] the process-wide configuration
  def self.configuration
    @configuration ||= Configuration.new
  end

  # @yieldparam config [Configuration]
  # @return [Configuration]
  def self.configure
    yield(configuration) if block_given?
    configuration
  end

  # Classify a set of repository paths into lifecycle cohorts.
  #
  # @param paths [Array<String>] repository roots on disk
  # @return [Portfolio] the classified portfolio
  def self.inventory(paths)
    Portfolio.scan(Array(paths))
  end

  # Run every detector over a repository and return its discovered facts.
  #
  # @param path [String] repository root on disk
  # @return [DiscoveryResult]
  def self.discover(path)
    Discovery.new(Repository.at(path)).run
  end

  # Resolve the effective vitality contract for a repository: discovery plus
  # the inferred (or declared) profile plus any .reanimator.yml overrides,
  # all clamped by the non-bypassable safety floor.
  #
  # @param path [String] repository root on disk
  # @param intent [Symbol, nil] override the inferred lifecycle intent
  # @return [EffectiveContract]
  def self.contract(path, intent: nil)
    repository = Repository.at(path)
    repository.intent = intent if intent
    EffectivePolicyResolver.new(repository).resolve
  end

  # Measure a read-only proof-of-life baseline for a repository.
  #
  # @param path [String] repository root on disk
  # @param execute [Boolean] actually run discovered checks (bounded,
  #   read-only) rather than only planning them
  # @param intent [Symbol, nil] override the inferred lifecycle intent
  # @return [Baseline]
  def self.baseline(path, execute: false, intent: nil)
    BaselineRunner.new(contract(path, intent: intent), execute: execute).run
  end

  # Capture the contract a repository resolves to right now, in a form that can
  # be recorded and compared later.
  #
  # @param path [String] repository root on disk
  # @param intent [Symbol, nil] override the inferred lifecycle intent
  # @return [ContractSnapshot]
  def self.snapshot(path, intent: nil)
    ContractSnapshot.of(contract(path, intent: intent))
  end

  # Detect configuration drift (section 06): compare the contract a repository
  # resolves to now against a previously recorded snapshot, classifying each
  # difference as a policy change (a human should look) or a benign one.
  #
  # @param path [String] repository root on disk
  # @param since [String, ContractSnapshot] a recorded snapshot, or a path to one
  # @param intent [Symbol, nil] override the inferred lifecycle intent
  # @return [DriftReport]
  def self.drift(path, since:, intent: nil)
    previous = since.is_a?(ContractSnapshot) ? since : ContractSnapshot.load(since.to_s)
    DriftDetector.between(previous, snapshot(path, intent: intent))
  end

  # Detect configuration drift across several repositories at once. Each
  # repository is compared against its own recorded snapshot - its committed
  # `.reanimator-snapshot.json`, or a file in `snapshots` keyed by
  # repository - and the result is a triage list rather than one verdict.
  #
  # @param paths [Array<String>] repository roots on disk
  # @param snapshots [String, nil] a directory of recorded snapshots, for
  #   repositories you cannot commit a file into
  # @param record [Boolean] also write each repository's current snapshot
  # @param intent [Symbol, nil] override the inferred lifecycle intent
  # @param name [String] portfolio name for the report header
  # @return [PortfolioDrift]
  def self.portfolio_drift(paths, snapshots: nil, record: false, intent: nil, name: "portfolio")
    PortfolioDrift.scan(
      paths, store: SnapshotStore.new(directory: snapshots),
      record: record, intent: intent, name: name
    )
  end

  # Default environment-variable names where each hosted provider's credentials
  # would live. Credentials are never read from a repository (section 08).
  CREDENTIAL_REFS = {
    codex: "OPENAI_ACCESS_TOKEN",
    claude: "ANTHROPIC_API_KEY",
    amp: "AMP_API_KEY"
  }.freeze

  # Commission a coding agent: prove it can plan and patch a synthetic repair on
  # a disposable fixture, graded independently, without any repository write.
  #
  # @param provider [Symbol] :local (default), :codex, :claude, or :amp
  # @return [Commissioning::Report]
  def self.commission(provider: :local, **connection_options)
    connection =
      if provider.to_sym == :local
        AgentConnection.local(**connection_options)
      else
        AgentConnection.new(
          provider: provider, credentials_ref: CREDENTIAL_REFS[provider.to_sym], **connection_options
        )
      end
    Commissioning::Test.new(Agents.for(connection)).run
  end

  # Attempt one bounded repair for a repository's first failing required
  # criterion. Read-only with respect to the repository: the result is a
  # recorded {Run} whose most eventful outcome is a *proposed* draft PR, never a
  # write or submission.
  #
  # @param path [String] repository root on disk
  # @param provider [Symbol] agent provider (:local by default)
  # @param task_class [Symbol] the task class governing autonomy (section 11)
  # @return [Run]
  def self.repair(path, provider: :local, task_class: :patch_dependency)
    RepairRun.new(contract(path), provider: provider, task_class: task_class).run
  end

  # Repairs the committed HEAD of a repository root and, when the repair
  # verifies, writes a {Proposal} that `submit` can open as a draft pull
  # request (section 11 submit rung). The repair runs against an export of
  # HEAD, so what is verified is exactly what a pull request is built on.
  #
  # @param to [String] where to write the proposal
  # @return [Array(Run, String)] the run, and the proposal path (nil when the
  #   repair did not produce a verified change)
  def self.propose(path, to:, provider: :local, task_class: :patch_dependency)
    CommittedTree.export(path) do |tree|
      contract = EffectivePolicyResolver.new(tree.repository).resolve
      run = RepairRun.new(contract, provider: provider, task_class: task_class).run
      next [run, nil] unless run.outcome == :draft_pr

      [run, Proposal.build(run.proposed_change, tree: tree, contract: contract, task_class: task_class).write(to)]
    end
  end

  # Opens a written proposal as a draft pull request. Runs no repository code
  # and no git; it is the only step that needs REANIMATOR_GITHUB_TOKEN.
  #
  # @return [Submitter::Outcome]
  def self.submit(proposal_path)
    Submitter.new.submit(Proposal.load(proposal_path))
  end

  # Infer the compatibility graph for a set of repository paths: which
  # repositories must stay alive together, and what proves each edge.
  #
  # @param paths [Array<String>]
  # @return [Array<Family>]
  def self.families(paths)
    FamilyInference.call(inventory(paths))
  end

  # Evaluate cross-repository gates for the inferred families. Read-only by
  # default: each downstream check only runs when execution is requested, and
  # then in a disposable copy of the downstream repository.
  #
  # @param paths [Array<String>]
  # @param family [Symbol, String, nil] limit to one family id
  # @param execute [Boolean]
  # @return [Array<Array(Family, Array<Family::GateResult>)>]
  def self.family_gates(paths, family: nil, execute: false)
    found = families(paths)
    found = found.select { |f| f.id == family.to_sym } if family
    found.map { |f| [f, Family::GateRunner.new(f, execute: execute).run] }
  end

  # Adapters for every built-in provider, with default connections - the roster
  # the CLI lists with availability.
  # @return [Array<Agents::Adapter>]
  def self.adapters
    Agents.providers.map do |provider|
      connection =
        if provider == :local
          AgentConnection.local
        else
          AgentConnection.new(provider: provider, credentials_ref: CREDENTIAL_REFS[provider])
        end
      Agents.for(connection)
    end
  end
end
