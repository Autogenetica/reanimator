# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Configuration drift (section 06): `ContractSnapshot` records what a
  repository was required to prove at a point in time, and `DriftDetector`
  compares a later resolution against it. Every difference is classified by one
  question — *is less being proven than before?* A narrowed runtime matrix, a
  removed security gate, a dropped required obligation, a widened autonomy
  grant or a fresh waiver are **policy changes** and ask for a human; a renamed
  test command, an added check or a withdrawn waiver are **benign** and do not
  interrupt anyone. The snapshot carries discovered evidence as well as the
  declared file, so drift that never touches `.frankenstein.yml` is still seen.
- CLI: `frankenstein drift [--since FILE] [--save FILE]`, exiting non-zero on a
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
- CLI: `frankenstein families` and `frankenstein gates [--execute] [--family ID]`.

- Waivers (section 09): explicit, attributable, optionally time-bounded
  exceptions declared in `.frankenstein.yml`. A waived required criterion is
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
- `.frankenstein.yml` reader/writer with lossless round-trip.
- Baseline runner with isolated evaluators (command, http-smoke, repository
  integrity, documentation, support matrix), bounded/opt-in execution, and
  proof-of-life assessment.
- Reporters mirroring the specification artifacts: the GitHub Check surface, the
  full baseline report, the Appendix A portfolio baseline, discovery, contract,
  and inventory.
- A Thor CLI (`frankenstein inventory|discover|contract|baseline|portfolio`).
- Coding-agent adapters (section 08): a portable `Agents::Adapter` contract, a
  fully working local rule-based agent, and honest hosted-provider stubs
  (Codex/Claude/Amp) that report themselves unavailable until connected.
- Account/organization `AgentConnection` (credentials referenced, never stored)
  and `AgentProfile` with a commissioned readiness verdict.
- Commissioning: a six-step synthetic repair against a disposable fixture,
  graded independently by Frankenstein's own evaluators, with verifier
  isolation and anti-gaming (a patch that touches a protected/verifier path is
  refused) enforced structurally.
- Routing (`Routing::Router`): auto, pinned, ordered, task-routed, local-only,
  and manual strategies, each producing a visible explanation; fallback is only
  ever a declared profile that shares the data-handling policy.
- Autonomy ladder and permission model (section 11): `AutonomyLevel`,
  `TaskClass` defaults, and `PermissionModel` that intersects task-class
  defaults with the repository's enabled autonomy and the safety floor.
- CLI additions: `frankenstein agents|commission|permissions`.
- Bounded repair (sections 11, 13, 17): `RepairRun` orchestrates baseline →
  obligation → permission check → routing → isolated agent repair → independent
  re-verification → a materialized `ProposedChange` (draft PR), recorded as an
  immutable `Run` in the ledger. It writes nothing to the repository - a
  proposed draft PR is an artifact, and submission is a separate, opt-in step.
- `Obligation` (idempotent, deduplicated), `ProposedChange`, `Run` (section 17
  ledger), and an `Isolation` disposable-workspace helper.
- CLI addition: `frankenstein repair`.

### Fixed

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
