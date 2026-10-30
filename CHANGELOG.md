# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Escalation delivery** (section 16). `baseline`, `portfolio` and `repair` now
  exit `2` when a human is needed — a required criterion failed or is unproven
  (including checks asked to execute that could not), or a repair produced
  anything but a healthy no-op — keeping
  `1` for Reanimator itself failing, including an unreadable portfolio path.
  Inside GitHub Actions each blocking finding becomes an `::error` annotation,
  each advisory problem a `::notice`, and the check surface is appended to the
  job summary. Reports are printed between `::stop-commands::` markers so
  repository text cannot forge or silence an annotation, and `--format json`
  stays valid JSON.

- **Network egress enforcement** (section 12). A security posture's network rule
  was a label; it is now enforced or refused. Under `strict` and `local`, which
  deny egress, every executed check runs inside an empty network namespace
  (unprivileged `unshare` on Linux) — verified by an outbound connection that
  succeeds outside the namespace and cannot even resolve inside it. Where that
  cannot be enforced, the baseline refuses to execute, marks each command
  criterion `skipped` with the reason, and says so on the `Mode:` line; it never
  runs unprotected. `balanced` stays unrestricted and now says plainly that its
  package-registry allowlist is advisory. Family gates are held to the
  downstream member's posture, and a bounded repair whose baseline did not
  execute stops safely instead of reading the empty result as a clean bill of
  health.

### Changed

- **`SupportMatrix` catches narrowed support.** It credited any CI Ruby matrix;
  it now compares the declared floor with CI's lowest pinned release across
  every workflow, and a matrix that rose above the floor, or pins no specific
  release, is missing evidence. Workflows are parsed as YAML: every job's
  `strategy.matrix` Ruby list counts, less what `exclude:` removes, plus
  `include:` entries, kept as written. A single job's setup-ruby version counts
  only when no workflow has a matrix, so a lint job pinned to an old Ruby
  cannot stand in for the tests. Workflows using YAML aliases give no evidence
  (an alias bomb is repository input). Gemspec requirements written as arrays —
  on one line or several — or `Gem::Requirement.new(...)` are read; `>= 0` sets
  no floor.
- **An unquoted whole-number Ruby in a matrix reads as a bare major.** YAML
  turns `3.0` into a number that Actions renders as `3`, which setup-ruby reads
  as the latest 3.x, so Reanimator now reads it the same way (and `3.10` as
  `3.1`, as YAML does). A snapshot recorded with 0.1.0 may then show `3.0`
  removed and `3` added; quote matrix versions, and re-record the snapshot.
- **Drift snapshots record every workflow's Ruby matrix,** not just the first,
  so drift and the baseline agree. Re-recording a snapshot may show a wider
  matrix than before; that is reported as benign.
- **A web application's boot smoke is `unavailable`, a new status, not missing
  evidence.** Reanimator does not provision a running service yet; the gap is
  its own, so the repository stays Unproven without being asked to act on it.
- **Library warnings go to stderr, one line each,** so `--format json` stays
  parseable and a message quoting repository content cannot become a workflow
  command of its own.
- **A repair with nothing to fix but something unproven escalates** instead of
  reporting a healthy no-op. When the only gap is proof Reanimator cannot
  establish yet, the no-op says so rather than "all required criteria pass".

## [0.1.0] - 2026-10-28

### Changed

- **The product is now Reanimator** (ADR-006). The gem name `frankenstein` is
  held on RubyGems by an actively downloaded Prometheus library, so 0.1.0 could
  not ship under it — but the better reason is that Frankenstein names a single
  dramatic act of revival, and this tool does something else: it proves,
  continuously and read-only, that a repository has not quietly rotted. Gem
  `reanimator`, module `Reanimator`, command `reanimator`, contract file
  `.reanimator.yml`, snapshot file `.reanimator-snapshot.json`, environment
  variables `REANIMATOR_*`. Nothing is published yet, so no existing
  installation or contract file is affected.

### Added

- Security posture enforcement (section 12). The posture was a label; it is now
  a decision with consequences. `SecurityControl` registers the controls a
  posture can require - dependency review, secret scanning, static analysis,
  security policy, ownership - each named by **obligation rather than tool**, so
  Dependabot, `bundler-audit` and `actions/dependency-review-action` all satisfy
  "dependency risk is reviewed" and a repository that already solved the problem
  its own way is credited instead of asked to adopt ours.
  `SecurityPosture#obligations` says which controls each posture makes binding:
  `strict` blocks without a security policy, dependency review and secret
  scanning; `local` blocks without secret scanning, because committed secrets
  are the one risk that does not care whose runner it is; `balanced` reports the
  same gaps without blocking; `custom` implies nothing, because "no hidden
  relaxation from a preset" cuts both ways.
- `Evaluators::SecurityEvidence`, a native evaluator that grades one control
  from discovered evidence - so it runs in the read-only default, with no
  execution, and reports a gap as *missing evidence* with the remedy attached
  rather than as a silent pass. Before this, a repository with no security gate
  at all could read **Alive at 100%**: nothing in the contract ever asked.
- `reanimator contract` now states the posture in plain language and lists
  exactly which controls it requires and which it merely reports. Section 12
  asks for security to be part of onboarding rather than a hidden settings page.
- Portfolio drift (section 06 applied to the portfolio of section 04).
  `reanimator drift` now takes several paths and returns a triage list rather
  than one verdict: repositories needing a human first, with the reason for each
  policy change; then repositories that merely changed; then the unchanged; then
  the ones with nothing recorded. `PortfolioDrift` is the value object,
  `Reanimator.portfolio_drift(paths)` the library call, and the exit status is
  still non-zero only when something actually needs a decision.
- `SnapshotStore` decides where a repository's recorded snapshot lives, and is
  the only thing that writes one. The default is **in the repository**,
  committed as `.reanimator-snapshot.json` beside `.reanimator.yml`, so a
  policy change arrives as a diff in a pull request rather than as state hidden
  inside a tool. `--snapshots DIR` keeps them portfolio-side, keyed by
  repository, for repositories you cannot commit a file into.
- `reanimator drift --record` writes the snapshot where it belongs, so neither
  recording nor comparing needs a remembered path any more: `reanimator drift`
  on its own now compares against the committed snapshot when there is one. The
  reports name the command that re-records *this* snapshot rather than a
  generic `--save FILE`.

- Configuration drift (section 06): `ContractSnapshot` records what a
  repository was required to prove at a point in time, and `DriftDetector`
  compares a later resolution against it. Every difference is classified by one
  question — *is less being proven than before?* A narrowed runtime matrix, a
  removed security gate, a dropped required obligation, a widened autonomy
  grant or a fresh waiver are **policy changes** and ask for a human; a renamed
  test command, an added check or a withdrawn waiver are **benign** and do not
  interrupt anyone. The snapshot carries discovered evidence as well as the
  declared file, so drift that never touches `.reanimator.yml` is still seen.
- CLI: `reanimator drift [--since FILE] [--save FILE]`, exiting non-zero on a
  policy change so CI can gate on it. The only file written is the one named
  with `--save`.

- Repository families (section 10): related repositories are treated as a
  compatibility graph rather than isolated targets. `Relationship` carries the
  seven typed edges, `Family` holds members/roles/gates (and parses the section
  10 family-policy shape), and `FamilyInference` derives families from portfolio
  structure - a project with its `-examples` suite, `-example-*` deployment
  samples, `-docs`, or a `<host>-<project>` plugin. Declaration wins over
  inference on both ends of an edge.
- `Family::GateRunner` proves each edge by running the downstream member's own
  check (a smoke script, else its discovered tests) read-only, bounded, and in a
  disposable copy - a candidate change upstream triggers downstream checks
  without opening anything downstream. A failure names **the exact edge that
  broke**, not merely the repository that ran.
- CLI: `reanimator families` and `reanimator gates [--execute] [--family ID]`.

- Waivers (section 09): explicit, attributable, optionally time-bounded
  exceptions declared in `.reanimator.yml`. A waived required criterion is
  recorded as **accepted risk** — not counted as verified, kept out of the
  Verified Vitality Rate, and no longer blocking — while an expired waiver
  fails closed. `Waiver`, `EffectiveContract#waiver_for`,
  `Baseline#accepted_risks`/`#unresolved_required`, and accepted-risk reporting.

- Canonical domain model: lifecycle intent, vitality profiles (Ruby-first),
  discovered facts with provenance and confidence, acceptance criteria, and the
  proof-of-life state vocabulary.
- Read-only discovery with detectors for Bundler, Ruby gems, Rails apps,
  discovered commands, GitHub Actions (CI matrix + security controls),
  repository security controls, forks, operational proof, and relationships.
- Portfolio intake: cohort classification and a recommended onboarding set that
  never preselects everything.
- `EffectivePolicyResolver` and a non-bypassable `SafetyFloor` implementing the
  section 07 precedence rules (owner declaration wins; nothing loosens the
  floor; merge disabled in v1).
- `.reanimator.yml` reader/writer with lossless round-trip.
- Baseline runner with isolated evaluators (command, http-smoke, repository
  integrity, documentation, support matrix), bounded/opt-in execution, and
  proof-of-life assessment.
- Reporters mirroring the specification artifacts: the GitHub Check surface, the
  full baseline report, the Appendix A portfolio baseline, discovery, contract,
  and inventory.
- A Thor CLI (`reanimator inventory|discover|contract|baseline|portfolio`).
- Coding-agent adapters (section 08): a portable `Agents::Adapter` contract, a
  fully working local rule-based agent, and honest hosted-provider stubs
  (Codex/Claude/Amp) that report themselves unavailable until connected.
- Account/organization `AgentConnection` (credentials referenced, never stored)
  and `AgentProfile` with a commissioned readiness verdict.
- Commissioning: a six-step synthetic repair against a disposable fixture,
  graded independently by Reanimator's own evaluators, with verifier
  isolation and anti-gaming (a patch that touches a protected/verifier path is
  refused) enforced structurally.
- Routing (`Routing::Router`): auto, pinned, ordered, task-routed, local-only,
  and manual strategies, each producing a visible explanation; fallback is only
  ever a declared profile that shares the data-handling policy.
- Autonomy ladder and permission model (section 11): `AutonomyLevel`,
  `TaskClass` defaults, and `PermissionModel` that intersects task-class
  defaults with the repository's enabled autonomy and the safety floor.
- CLI additions: `reanimator agents|commission|permissions`.
- Bounded repair (sections 11, 13, 17): `RepairRun` orchestrates baseline →
  obligation → permission check → routing → isolated agent repair → independent
  re-verification → a materialized `ProposedChange` (draft PR), recorded as an
  immutable `Run` in the ledger. It writes nothing to the repository - a
  proposed draft PR is an artifact, and submission is a separate, opt-in step.
- `Obligation` (idempotent, deduplicated), `ProposedChange`, `Run` (section 17
  ledger), and an `Isolation` disposable-workspace helper.
- CLI addition: `reanimator repair`.

### Fixed

- A criterion whose evaluator **errored** no longer reads as proof. `:error` was
  neither "failed" nor "unproven", so a required check that could not be
  evaluated left the repository green - the one outcome a verifier must never
  produce. "We could not tell" is now unproven.
- The layers that contribute obligations - profile defaults, posture security
  controls, owner declarations - are merged by criterion id instead of
  concatenated, so a declared check *replaces* the default it names rather than
  appearing twice alongside it. Precedence follows section 07: the owner's
  declaration wins.
- A portfolio drift run fails closed on a snapshot it cannot read. An
  unreadable or corrupt snapshot is reported as needing review rather than
  counted among the quiet repositories - "we could not tell" is not "nothing
  changed", and corrupting a snapshot file must never be a way to make a drift
  gate pass. A repository with nothing recorded yet is still named without
  failing the gate: that is a first run, not a gap.
- One unreadable repository no longer ends a portfolio run; it becomes a failed
  entry and every other member still reports.

- `reanimator drift --format text` now prints text. With no `--since` it
  described the repository's current obligations in prose instead of emitting
  JSON, which contradicted its own `--format` flag; `--format json` is
  unchanged for machine use.
- A drift report now ends by saying how to accept drift that was intended,
  naming the exact `--save` command - the build log is the only place the
  maintainer is looking.
- Drift comparison fails closed and refuses input it cannot trust. A snapshot
  file is ordinary input, so one that is valid JSON but not a snapshot, or a
  path that is a directory, now fails as a clean error instead of a raw
  `TypeError`/`Errno` backtrace - as does `--save` into a directory that does
  not exist. A waiver whose new expiry cannot be parsed is treated as a policy
  change rather than silently filed as "shortened".
- A recorded `ContractSnapshot` is genuinely immutable: its criteria, paths and
  matrices can no longer be edited after the fact (a bare `freeze` left them
  writable), and recording a contract no longer freezes the live contract.
- Drift identifies a repository by its git origin when both snapshots carry
  one, so two checkouts that merely share a directory name are refused instead
  of reporting the most dangerous possible answer: "no drift".

- Baseline/repair command execution now runs in a disposable copy of the
  repository, never the original working tree (spec section 14), so `gem build`,
  tests, and other checks cannot leave artifacts in the real checkout.
- Bounded commands run as their own process group and terminate the whole group
  on timeout, so a spawned child cannot outlive the bound.
- Protected-path matching is depth-correct: a protected `dir/**` now covers
  nested files (e.g. `.github/workflows/nested/*.yml`) instead of only the top
  level, and allow globs cover nested paths too.
- The `tests` acceptance criterion now carries the provenance of its discovered
  command (a criterion-id/fact-key mismatch previously dropped it).
- Bounded repair proves agent readiness by commissioning before routing, rather
  than assuming readiness from mere availability.
- Robust to non-UTF-8 input: repository files and command output are read as
  scrubbed UTF-8, so a stray byte (or a C/US-ASCII locale) no longer makes a
  detector raise, get swallowed, and silently drop facts.
- `BoundedCommand` caps captured output (1 MiB) so a runaway command cannot
  exhaust memory, while still draining the pipe so the child never blocks.
- Swallowed detector failures now log their exception class and origin, so a
  hidden bug stays diagnosable instead of silently dropping facts.
- `Baseline` answers `failing_required`, `unproven_required`,
  `first_failing_required_criterion`, `result_for`, and `verified_required_ids`,
  removing duplicated result-digging from the repair flow and reporters.

[Unreleased]: https://github.com/Autogenetica/reanimator/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Autogenetica/reanimator/releases/tag/v0.1.0
