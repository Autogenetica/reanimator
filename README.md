# Frankenstein

**Turn repository intent into a verified, low-friction stewardship contract.**

> The first successful Frankenstein run should prove something useful without
> changing a single line of code.

Frankenstein reads a repository, infers what *healthy* means for it, and proves
that health **read-only** — before any coding agent or write permission is ever
involved. It classifies lifecycle intent, discovers a vitality contract from
evidence, resolves an effective policy against a non-bypassable safety floor,
and produces a proof-of-life baseline.

This gem implements the read-only foundation of the
[Onboarding & Configuration Specification](#specification-coverage): delivery
slices 1–2 (inventory & intent, discovery & baseline) plus the canonical schema
and effective-policy resolver. It is the "trustworthy heartbeat" the spec says
to ship before building an autonomous surgeon.

## Installation

```ruby
# Gemfile
gem "frankenstein"
```

```console
$ bundle install
# or, standalone:
$ gem install frankenstein
```

Requires Ruby >= 3.3.

## The onboarding path, on the command line

Every command is **read-only by default** and maps to an onboarding stage.

### 1. Classify before acting — `inventory`

```console
$ frankenstein inventory ~/src/*
Portfolio inventory — 12 repositories
Recommended for onboarding: agentic, claude_memory, eliza

Active original repositories → suggest maintain:
  - agentic — Active original repository with recognizable structure.
Forks → suggest upstream:
  - langchainrb — The repository is a fork; defaulting to upstream observation.
```

Frankenstein never preselects every repository — it recommends a small,
high-confidence set that can reach a useful baseline quickly.

### 2. Find proof before asking for policy — `discover`

```console
$ frankenstein discover
Suggested profile: ruby-gem (high) — A gemspec indicates a published gem.

ecosystem:
  [high] Packaged and released as a Ruby gem.  ← widget.gemspec (file_present)
commands:
  [high] Tests run with RSpec.  ← .rspec (command_inference): bundle exec rspec
support matrix:
  [medium] Declared Ruby support: >= 3.1.0.  ← widget.gemspec (version_pin): >= 3.1.0
```

Every discovered fact carries its **provenance and confidence**, so the tool can
always answer *"Why does Frankenstein believe this?"*

### 3. Review the effective contract — `contract`

```console
$ frankenstein contract
Effective contract — codenamev/widget
Intent:   maintain (provisional)
Profile:  ruby-gem (inferred) — A published Ruby gem: resolves, tests, lints, and builds.
Security: balanced posture
Autonomy: observe=automatic  diagnose=automatic  repair=disabled  submit=disabled  merge=disabled

Criteria (* = required):
  * tests: Test suite passes. — bundle exec rspec
  ...
Protected paths (elevated review to change):
  - .frankenstein.yml
  - .github/workflows/**
```

Export a minimal, round-trippable `.frankenstein.yml`:

```console
$ frankenstein contract --export
version: 1
intent: maintain
profile: ruby-gem
```

### 4. Measure a proof-of-life baseline — `baseline`

Read-only by default (native checks run; commands are *planned*):

```console
$ frankenstein baseline
State:   UNPROVEN — A claim exists but sufficient executable evidence is absent or stale.
Mode:    read-only (planned)
```

Opt in to bounded execution to actually prove life:

```console
$ frankenstein baseline --execute
State:   ALIVE — All due obligations have fresh passing evidence and no unapproved blocking risk.
Mode:    executed (bounded, read-only)
Verified Vitality Rate: 100% (3/3 required)
  ✓* tests: Test suite passes. — bundle exec rspec (1.69s)
  ✓* build: Gem builds. — gem build widget.gemspec (0.32s)

NO SOURCE CHANGES WERE MADE
```

Other formats: `--format check` (the GitHub Check surface) and `--format json`.

### 5. Prove an agent is ready — `agents` and `commission`

The agent is a replaceable life-force adapter: a repair provider is *commissioned*
against a disposable fixture and graded independently — **without any repository
write**.

```console
$ frankenstein agents
Coding agents:
  ✓ local (available) [plan, patch, repository_edit, sandbox_exec]
  ◦ codex (unavailable) [...] — No credentials found (set OPENAI_ACCESS_TOKEN); connect the codex provider first.

$ frankenstein commission
Commissioning — local
Readiness: READY
Objective: arithmetic (at risk → alive)
Cost: $0.00  Latency: 0.001s  Tools: repository_edit, patch  Network: none
A connected profile is proven ready. NO REPOSITORY WRITES WERE REQUIRED.
```

The agent proposes a **patch as data**; the harness applies it to a separate,
clean copy and grades it with Frankenstein's own evaluators. A patch that reaches
for a protected or verifier path is refused — the anti-gaming rule, enforced.

### 6. Bounded repair — `repair`

A repair is found, applied in an isolated workspace, and **re-verified
independently** before anything is proposed. The result is a *draft PR
artifact* — never a write, never a submission.

```console
$ frankenstein repair            # on a healthy repo
Outcome:  NO-OP (healthy)

$ frankenstein repair            # repair not yet enabled in the contract
Outcome:  ESCALATION
Reason:   Repair is not enabled for patch_dependency (max autonomy diagnose); enable repair to proceed.

$ frankenstein repair            # repair enabled, a fixable failure present
Outcome:  DRAFT PR (proposed, not submitted)
Evidence: at_risk → alive
Proposed draft PR:
  branch: frankenstein/repair-arithmetic-901cec8a
  title:  Fix: add(2, 2) equals 4.
NO SOURCE WAS WRITTEN TO THE REPOSITORY.
```

Every outcome is recorded as an immutable run-ledger entry (`no_op`, `report`,
`draft_pr`, `escalation`, `safe_stop`). Submitting a proposed change to GitHub is
a deliberate, separate step — not something repair does on its own.

### Repository families — `families` and `gates`

Related projects are a compatibility graph, not isolated targets. Families are
inferred from portfolio structure (a project and its `-examples` suite,
`-example-*` deployment samples, `-docs`, or a `<host>-<project>` plugin):

```console
$ frankenstein families ~/src/*
Repository families — 2 families (4 repositories that must stay alive together)

agentic:
  - agentic (library)
  - agentic-examples (compatibility suite)
  edge: agentic -> agentic-examples (compatibility suite)
  gate: agentic requires its own proof command in agentic-examples
```

`gates` proves each edge by running the downstream member's own check — read-only,
bounded, in a disposable copy, so an upstream change triggers downstream checks
**without opening anything downstream**. A failure names the exact edge:

```console
$ frankenstein gates ~/src/* --execute
Family gates — slimer
  ✗ slimer -> slimer-example-docker (deployment example) — bin/smoke failed.
BROKEN EDGE: slimer -> slimer-example-docker (deployment example)
```

A repository can also declare its membership (`family: {id:, role:}`), and a full
section 10 family policy with explicit `members:` and `gates:` is parsed as-is.
Declaration always wins over inference.

### Accepted risk — waivers

Sometimes a known failure is a deliberate, tracked decision, not a gap. A waiver
records it as **accepted risk** — visible, attributable, and kept out of the
vitality rate — without pretending it passed:

```yaml
# .frankenstein.yml
version: 1
intent: maintain
profile: ruby-gem
waivers:
  - target: boot                       # the acceptance-criterion id
    reason: "hardware-only smoke; tracked in OPS-7"
    expires: 2030-01-01                # optional; past this it fails closed
```

The baseline then reports `boot` under "Accepted risk (waived)" instead of as a
blocker, and the repository can be **Alive** with the risk shown separately. An
expired waiver stops applying and the obligation is blocking again.

### Resolved autonomy — `permissions`

```console
$ frankenstein permissions
Permissions — codenamev/widget (autonomy: observe=automatic diagnose=automatic repair=disabled …)
  Patch dependency update: max=diagnose | observe=auto diagnose=auto repair=off submit=off merge=off …
  CI or verifier modification: max=diagnose | … [elevated review]
```

Task-class defaults (section 11) are intersected with the repository's *enabled*
autonomy and the safety floor: with repair/submit opt-in and off, everything
clamps to diagnose; merge is always off in v1.

### The portfolio baseline (Appendix A)

```console
$ frankenstein portfolio ~/src/* --name codenamev
FRANKENSTEIN BASELINE
Portfolio: codenamev
Mode: read-only

ALIVE
  agentic
UNPROVEN
  ups
    - Boot smoke against /up needs a running service; not established in a read-only baseline.

NO SOURCE CHANGES WERE MADE
No coding agent was required.
```

## Library API

The CLI is a thin shell over a plain Ruby API — the same "80% path" in one call:

```ruby
require "frankenstein"

Frankenstein.inventory(paths)          #=> Frankenstein::Portfolio
Frankenstein.discover(path)            #=> Frankenstein::DiscoveryResult
Frankenstein.contract(path)            #=> Frankenstein::EffectiveContract
Frankenstein.baseline(path, execute: true) #=> Frankenstein::Baseline

baseline = Frankenstein.baseline(".")
baseline.state.to_sym                  #=> :unproven
baseline.verified_vitality_rate        #=> 0.0
baseline.to_h                          # fully serializable
```

## Core model

The nouns that stay stable while implementations evolve (spec section 02):

| Concept | Class |
| --- | --- |
| Lifecycle intent | `LifecycleIntent` (maintain, monitor, preserve, incubate, retire, upstream, ignore) |
| Vitality profile | `VitalityProfile` / `Profiles` (ruby-gem, ruby-cli, rails-app, rails-legacy, …) |
| Discovered fact | `DiscoveredFact` (+ `Provenance`, `Confidence`) |
| Effective contract | `EffectiveContract` (+ `EffectivePolicyResolver`, `SafetyFloor`) |
| Baseline | `Baseline` (+ `BaselineRunner`, `Evaluators`, `ProofOfLife`) |
| Repository state | `RepositoryState` (alive, at risk, needs you, recovering, unproven, sleeping, diverged, retired) |

Two rules are **enforced**, not just documented:

- An owner-declared contract wins over inference.
- Neither a declaration nor discovery may loosen the safety floor — merge stays
  off in v1, verifier and contract paths stay protected, and a task that
  modifies the rules of proof cannot use them to approve itself.

## Specification coverage

| Spec area | Status |
| --- | --- |
| 01–02 Model, goals, constraints | ✅ Implemented |
| 04–05 Portfolio intake, lifecycle intent | ✅ `Portfolio`, `Classifier`, `Cohort` |
| 06 Discovery by confirmation | ✅ `Detectors::*`, provenance, confidence |
| 07 Configuration & precedence | ✅ `EffectivePolicyResolver`, `SafetyFloor` |
| 09 Acceptance criteria, verifier isolation & waivers | ✅ `AcceptanceCriterion`, `Evaluators`, `Waiver` (accepted risk) |
| 14–15 Baseline & proof-of-life | ✅ `BaselineRunner`, `ProofOfLife`, `Reports` |
| 08 Agent connections, commissioning, routing | ✅ `Agents::*`, `Commissioning`, `Routing::Router` |
| 11 Autonomy ladder & permission model | ✅ `AutonomyLevel`, `TaskClass`, `PermissionModel` |
| 13 / 17 Bounded repair & run ledger | ✅ `RepairRun`, `Obligation`, `ProposedChange`, `Run` (no writes) |
| 18 MVP slices 1–4 | ✅ Inventory→baseline→commissioning→bounded repair |
| 10 Repository families & compatibility graphs | ✅ `Relationship`, `Family`, `FamilyInference`, `Family::GateRunner` |
| 12 Security controls | ⏳ Modeled; enforcement expands with submission |
| Draft-PR *submission* to GitHub | ⏳ Deliberate opt-in; artifact is ready, the write is not wired |
| GitHub App, web UI | ⏳ Explicitly later (spec sections 03, 18) |

See [`.architecture/decisions`](.architecture/decisions) for the reasoning
behind key choices.

## Development

```console
$ bin/setup          # install dependencies
$ bundle exec rake   # run specs and StandardRB
$ bin/console        # an IRB session with the gem loaded
```

## License

Released under the [MIT License](LICENSE.txt).
