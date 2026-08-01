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

Requires Ruby >= 3.1.

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
| 09 Acceptance criteria & verifier isolation | ✅ `AcceptanceCriterion`, `Evaluators` |
| 14–15 Baseline & proof-of-life | ✅ `BaselineRunner`, `ProofOfLife`, `Reports` |
| 18 MVP slices 1–2 | ✅ Inventory→intent, discovery→baseline |
| 08 Agent connections / commissioning | ⏳ Designed for; not in this slice |
| 10 Repository families | ⏳ Detected as relationships; gates deferred |
| 11–13 Autonomy, security controls, upgrades | ⏳ Modeled; enforcement expands with agents |
| GitHub App, web UI, draft-PR repair | ⏳ Explicitly later (spec sections 03, 18) |

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
