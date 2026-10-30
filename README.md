# Reanimator

**Turn repository intent into a verified, low-friction stewardship contract.**

An [Autogenetica](https://autogenetica.ai) system for self-maintaining software.

> The first successful Reanimator run should prove something useful without
> changing a single line of code.

Reanimator reads a repository, infers what *healthy* means for it, and proves
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
gem "reanimator"
```

```console
$ bundle install
# or, standalone:
$ gem install reanimator
```

Requires Ruby >= 3.3.

## The onboarding path, on the command line

Every command is **read-only by default** and maps to an onboarding stage.

### 1. Classify before acting — `inventory`

```console
$ reanimator inventory ~/src/*
Portfolio inventory — 12 repositories
Recommended for onboarding: agentic, claude_memory, eliza

Active original repositories → suggest maintain:
  - agentic — Active original repository with recognizable structure.
Forks → suggest upstream:
  - langchainrb — The repository is a fork; defaulting to upstream observation.
```

Reanimator never preselects every repository — it recommends a small,
high-confidence set that can reach a useful baseline quickly.

### 2. Find proof before asking for policy — `discover`

```console
$ reanimator discover
Suggested profile: ruby-gem (high) — A gemspec indicates a published gem.

ecosystem:
  [high] Packaged and released as a Ruby gem.  ← widget.gemspec (file_present)
commands:
  [high] Tests run with RSpec.  ← .rspec (command_inference): bundle exec rspec
support matrix:
  [medium] Declared Ruby support: >= 3.1.0.  ← widget.gemspec (version_pin): >= 3.1.0
```

Every discovered fact carries its **provenance and confidence**, so the tool can
always answer *"Why does Reanimator believe this?"*

### 3. Review the effective contract — `contract`

```console
$ reanimator contract
Effective contract — codenamev/widget
Intent:   maintain (provisional)
Profile:  ruby-gem (inferred) — A published Ruby gem: resolves, tests, lints, and builds.
Autonomy: observe=automatic  diagnose=automatic  repair=disabled  submit=disabled  merge=disabled

Security posture: balanced
  Approved package-registry network, hosted agents allowed, patch submission permitted, no major automatic repair.
  Required: none
  Advisory: dependency review, secret scanning, security policy

Criteria (* = required):
  * tests: Test suite passes. — bundle exec rspec
    security-dependency-review: Dependency risk is reviewed automatically. — security_evidence
  ...
Protected paths (elevated review to change):
  - .reanimator.yml
  - .github/workflows/**
```

Export a minimal, round-trippable `.reanimator.yml`:

```console
$ reanimator contract --export
version: 1
intent: maintain
profile: ruby-gem
```

### 4. Measure a proof-of-life baseline — `baseline`

Read-only by default (native checks run; commands are *planned*):

```console
$ reanimator baseline
State:   UNPROVEN — A claim exists but sufficient executable evidence is absent or stale.
Mode:    read-only (planned)
```

Opt in to bounded execution to actually prove life:

```console
$ reanimator baseline --execute
State:   ALIVE — All due obligations have fresh passing evidence and no unapproved blocking risk.
Mode:    executed (bounded, read-only; network not restricted; the balanced posture's package-registry allowlist is advisory)
Verified Vitality Rate: 100% (3/3 required)
  ✓* tests: Test suite passes. — bundle exec rspec (1.69s)
  ✓* build: Gem builds. — gem build widget.gemspec (0.32s)

NO SOURCE CHANGES WERE MADE
```

Execution is held to the security posture's network rule. Under `strict` or
`local`, which deny egress, every command runs inside an empty network namespace
(unprivileged `unshare` on Linux). Where that cannot be enforced, Reanimator
refuses to execute rather than running unprotected:

```console
$ reanimator baseline --execute   # strict posture, on macOS
State:   UNPROVEN — A claim exists but sufficient executable evidence is absent or stale.
Mode:    not executed — the strict posture requires denied network egress and this runner cannot enforce it (no network sandbox on arm64-darwin23)
  ◦* suite: The suite passes. — Not run: the strict posture requires denied network egress and this runner cannot enforce it (no network sandbox on arm64-darwin23).
```

Other formats: `--format check` (the GitHub Check surface) and `--format json`.

#### In CI — exit status and annotations

The exit status separates the tool from the repository, so CI goes red only
when a human is actually needed:

| Exit | Meaning |
| --- | --- |
| 0 | Nothing needs a human. |
| 1 | Reanimator could not do its job (bad input, an unreadable path or contract), or `drift` needs review. |
| 2 | A human is needed: a required criterion failed or is unproven (including checks that were asked to execute and could not), or a `repair` produced anything but a healthy no-op — a verified draft waiting for a human counts. |

Inside GitHub Actions the same findings also surface without anyone opening the
log: each blocking finding becomes an `::error` annotation, each advisory
criterion with a real problem a `::notice`, and the check surface is appended to
the job summary. One annotation per finding, per run. Reports quote text the
repository controls, so they are printed between `::stop-commands::` markers and
cannot forge or silence an annotation; `--format json` stays pure JSON.

```yaml
- run: bundle exec reanimator baseline --execute --format check
```

Advisory criteria never fail the job. To make one blocking — say, declared Ruby
support that CI no longer exercises — declare it required:

```yaml
# .reanimator.yml
acceptance:
  checks:
    - id: support_matrix
      claim: "Declared Ruby versions are exercised."
      evaluator: support_matrix
      required: true
```

### 5. Prove an agent is ready — `agents` and `commission`

The agent is a replaceable life-force adapter: a repair provider is *commissioned*
against a disposable fixture and graded independently — **without any repository
write**.

```console
$ reanimator agents
Coding agents:
  ✓ local (available) [plan, patch, repository_edit, sandbox_exec]
  ◦ codex (unavailable) [...] — No credentials found (set OPENAI_ACCESS_TOKEN); connect the codex provider first.

$ reanimator commission
Commissioning — local
Readiness: READY
Objective: arithmetic (at risk → alive)
Cost: $0.00  Latency: 0.001s  Tools: repository_edit, patch  Network: none
A connected profile is proven ready. NO REPOSITORY WRITES WERE REQUIRED.
```

The agent proposes a **patch as data**; the harness applies it to a separate,
clean copy and grades it with Reanimator's own evaluators. A patch that reaches
for a protected or verifier path is refused — the anti-gaming rule, enforced.

### 6. Bounded repair — `repair`

A repair is found, applied in an isolated workspace, and **re-verified
independently** before anything is proposed. The result is a *draft PR
artifact* — never a write, never a submission.

```console
$ reanimator repair            # on a healthy repo
Outcome:  NO-OP (healthy)

$ reanimator repair            # repair not yet enabled in the contract
Outcome:  ESCALATION
Reason:   Repair is not enabled for patch_dependency (max autonomy diagnose); enable repair to proceed.

$ reanimator repair            # repair enabled, a fixable failure present
Outcome:  DRAFT PR (proposed, not submitted)
Evidence: at_risk → alive
Proposed draft PR:
  branch: reanimator/repair-arithmetic-901cec8a
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
$ reanimator families ~/src/*
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
$ reanimator gates ~/src/* --execute
Family gates — slimer
  ✗ slimer -> slimer-example-docker (deployment example) — bin/smoke failed.
BROKEN EDGE: slimer -> slimer-example-docker (deployment example)
```

A repository can also declare its membership (`family: {id:, role:}`), and a full
section 10 family policy with explicit `members:` and `gates:` is parsed as-is.
Declaration always wins over inference.

### Configuration drift — `drift`

A contract is only trustworthy while it still describes the repository. Drift
detection compares what a repository resolved to when you recorded it against
what its evidence resolves to now, and sorts every difference by one question:
**is less being proven than before?**

```console
$ reanimator drift                       # what am I required to prove right now?
Contract snapshot — codenamev/widget
Intent:   maintain   Profile: ruby-gem   Security: balanced posture
Proves:   4 criteria (2 required)
Evidence: runtimes 3.3, 3.4 · security gates dependabot

Nothing was written. Record this with `reanimator drift --record` so later drift has something to be measured against.

$ reanimator drift --record
Recorded contract snapshot for codenamev/widget → .reanimator-snapshot.json

$ reanimator drift                       # now there is something to compare against
Configuration drift — codenamev/widget

Policy changes (review required) — 2
  ! supported runtime removed: 3.2
    The runtime matrix narrowed: a version that used to be exercised no longer is.
  ! security control removed: dependabot
    A security gate was removed; it is no longer part of the proof.

Benign changes — 1
  · criterion tests command: bundle exec rspec → bin/rspec
    The same obligation is proven by a differently spelled command.

REVIEW REQUIRED: 2 policy changes — less is being proven than before.

Intended? Re-record with: reanimator drift --record
```

A renamed test command is benign — the obligation did not move, only its
spelling. A narrowed matrix or a removed gate is a policy change nobody
necessarily decided on, so it is never buried in the benign list. The command
exits non-zero on policy drift, so CI can gate on it (and says how to accept
drift you meant). The snapshot captures
*discovered* evidence too — drift that never touches `.reanimator.yml` is
still caught.

The snapshot lives **in the repository**, committed as
`.reanimator-snapshot.json` beside `.reanimator.yml`. That is deliberate:
the contract and the record of what it last required are the same kind of
thing, and keeping both under review means a policy change arrives as a diff in
a pull request rather than as state hidden inside a tool.

#### Across a portfolio

Pass several paths and drift becomes a triage list. Each repository is compared
against its own snapshot, and one unreadable member never stops the rest:

```console
$ reanimator drift ~/src/*
REANIMATOR DRIFT
Portfolio: portfolio
Mode: read-only

REVIEW REQUIRED — 1 repository
  codenamev/widget
    1 policy change
      ! security control removed: dependabot
        A security gate was removed; it is no longer part of the proof.

CHANGED, BENIGN — 1 repository
  codenamev/doodad
    · criterion tests command: bundle exec rake spec → bundle exec rspec

UNCHANGED — 3 repositories
  codenamev/gadget
  codenamev/gizmo
  codenamev/thing

NOT RECORDED — 1 repository
  codenamev/fresh
    nothing to compare against yet

REVIEW REQUIRED: 1 policy change across 1 repository — less is being proven than before.
Intended? Re-record with: reanimator drift --record

NO FILES WERE WRITTEN. NO SOURCE CHANGES WERE MADE.
```

For repositories you cannot commit a file into, `--snapshots DIR` keeps them
side by side keyed by repository instead:

```console
$ reanimator drift ~/src/* --snapshots ~/.reanimator/snapshots --record
```

Three outcomes are deliberately distinct. A repository with **nothing
recorded** is named, not counted as fine, and does not fail the gate — a first
run has nothing to compare against. A repository whose snapshot **cannot be
read** does fail it: "we could not tell" is not "nothing changed", and
corrupting a snapshot must never be a way to pass. Benign change never fails
it at all.

### Security posture — what it actually binds

The posture is a named decision with consequences, not a label. It decides how
much security evidence a repository has to show; the project's shape does not.

```yaml
# .reanimator.yml
version: 1
intent: maintain
profile: ruby-gem
security:
  posture: strict      # strict | balanced | local | custom
```

| Posture | Blocks without evidence | Reported, not blocking |
| --- | --- | --- |
| `strict` (default for private repositories) | security policy, dependency review, secret scanning | static analysis, ownership |
| `balanced` (default for public repositories) | — | dependency review, secret scanning, security policy |
| `local` | secret scanning | dependency review |
| `custom` | — | — |

Controls are named by **obligation, not by tool**: "dependency risk is reviewed"
is satisfied by Dependabot, `bundler-audit`, or `actions/dependency-review-action`
alike, so a repository that already solved the problem its own way is credited
rather than asked to adopt ours. A control with no evidence is reported as
*missing evidence* with the remedy attached — never as a silent pass:

```console
  •  security-secret-scanning: Committed secrets are scanned for.
     — No secret scanning found. Add gitleaks or trufflehog to CI.
  ✓  security-policy: A security policy says how to report a vulnerability.
     — A security policy is published (SECURITY.md).
```

Under `strict` and `local` those gaps are blocking, so a repository with no
security evidence is **Unproven**, not Alive. When the gap is a deliberate,
tracked decision, accept it with a waiver rather than weakening the posture.

`custom` implies nothing in either direction: "no hidden relaxation from a
preset" means Reanimator adds no control you did not ask for, either.

### Accepted risk — waivers

Sometimes a known failure is a deliberate, tracked decision, not a gap. A waiver
records it as **accepted risk** — visible, attributable, and kept out of the
vitality rate — without pretending it passed:

```yaml
# .reanimator.yml
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
$ reanimator permissions
Permissions — codenamev/widget (autonomy: observe=automatic diagnose=automatic repair=disabled …)
  Patch dependency update: max=diagnose | observe=auto diagnose=auto repair=off submit=off merge=off …
  CI or verifier modification: max=diagnose | … [elevated review]
```

Task-class defaults (section 11) are intersected with the repository's *enabled*
autonomy and the safety floor: with repair/submit opt-in and off, everything
clamps to diagnose; merge is always off in v1.

### The portfolio baseline (Appendix A)

```console
$ reanimator portfolio ~/src/* --name codenamev
REANIMATOR BASELINE
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
require "reanimator"

Reanimator.inventory(paths)          #=> Reanimator::Portfolio
Reanimator.discover(path)            #=> Reanimator::DiscoveryResult
Reanimator.contract(path)            #=> Reanimator::EffectiveContract
Reanimator.baseline(path, execute: true) #=> Reanimator::Baseline
Reanimator.snapshot(path)            #=> Reanimator::ContractSnapshot
Reanimator.drift(path, since: file)  #=> Reanimator::DriftReport
Reanimator.portfolio_drift(paths)    #=> Reanimator::PortfolioDrift

baseline = Reanimator.baseline(".")
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
| 06 Discovery by confirmation & drift | ✅ `Detectors::*`, provenance, confidence, `DriftDetector`, `PortfolioDrift` |
| 07 Configuration & precedence | ✅ `EffectivePolicyResolver`, `SafetyFloor` |
| 09 Acceptance criteria, verifier isolation & waivers | ✅ `AcceptanceCriterion`, `Evaluators`, `Waiver` (accepted risk) |
| 14–15 Baseline & proof-of-life | ✅ `BaselineRunner`, `ProofOfLife`, `Reports` |
| 08 Agent connections, commissioning, routing | ✅ `Agents::*`, `Commissioning`, `Routing::Router` |
| 11 Autonomy ladder & permission model | ✅ `AutonomyLevel`, `TaskClass`, `PermissionModel` |
| 13 / 17 Bounded repair & run ledger | ✅ `RepairRun`, `Obligation`, `ProposedChange`, `Run` (no writes) |
| 18 MVP slices 1–4 | ✅ Inventory→baseline→commissioning→bounded repair |
| 10 Repository families & compatibility graphs | ✅ `Relationship`, `Family`, `FamilyInference`, `Family::GateRunner` |
| 12 Security controls | ✅ `SecurityControl`, `SecurityPosture#obligations`, `Evaluators::SecurityEvidence`, `EgressControl` (denied egress enforced on Linux, refused elsewhere; the balanced registry allowlist is advisory) |
| 16 Escalation delivery | ✅ Exit status 2, `Reports::Annotations`, `ActionsSurface` (annotations + job summary); `SupportMatrix` catches narrowed support |
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

Releases are manual and credential-free — see [RELEASING.md](RELEASING.md).

## License

Released under the [MIT License](LICENSE.txt).
