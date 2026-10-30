# Reanimator

Turn repository intent into a verified, low-friction stewardship contract.

**North star:** the first successful run proves something useful *without
changing a single line of code*. Read-only first, and read-only by default.

## How to work in this repo

- **Refactor after every commit.** Follow each behaviour change with a separate
  refactoring commit (Fowler's two hats), so the next change is easier to make.
  A refactoring commit must change **no spec** — the untouched suite is the
  proof that behaviour was preserved. When the change is a rename, say so
  plainly rather than pretending nothing moved.
- **Verify by running, not by asserting.** A green suite is necessary and not
  sufficient. Before claiming a slice works, run the CLI against a real fixture
  repository and read what it actually printed. Most bugs found here surfaced
  that way and not in RSpec.
- **Fail closed.** "We could not tell" is never proof. An unreadable snapshot,
  an expired waiver, an evaluator that errored, a corrupt input — each must
  block rather than pass quietly. Several real defects here were exactly this
  shape, so treat any new "we'll skip it if we can't read it" path as suspect.
- **Credit evidence that already exists.** Criteria and security controls are
  named by *obligation*, not by tool: Dependabot, `bundler-audit` and
  `actions/dependency-review-action` all satisfy "dependency risk is reviewed".
  Never ask a repository to re-declare something it has already proven.
- **The safety floor is not negotiable.** No layer may loosen verifier
  isolation, remove a protected path, or enable automatic merge in v1. If a
  feature needs to bend it, that is an ADR, not a patch.
- Design decisions live in `.architecture/decisions/`. Write an ADR when you
  make one; `ADR-006` is the model for recording rejected alternatives too,
  which is usually the more useful half.
- Commit messages explain **why** in prose, not what the diff already shows.

## Commands

```bash
bin/setup                                       # bundle install
bundle exec rake                                # specs + StandardRB (expect 288 examples; 1 pending off Linux)
bundle exec exe/reanimator baseline . --execute  # prove this repo on itself
bundle exec exe/reanimator contract .            # resolved contract, incl. security posture
bundle exec exe/reanimator drift .               # compare with the committed snapshot (CI does)
bundle exec exe/reanimator drift . --record      # re-record after an intended contract change
```

Ruby >= 3.3.0. CI exercises 3.3 and 3.4.

## State

0.1.0 is published to RubyGems via trusted publishing (no stored API key); see
`RELEASING.md` for the cut checklist. The README's specification-coverage table
is the authoritative map of what is implemented. Two files still say
"Frankenstein" on purpose: `ADR-006`, which records the rename, and the
changelog note explaining it.

This repository stewards itself: the `stewardship` CI job runs
`baseline . --execute` and `drift .` against the committed
`.reanimator-snapshot.json`. A policy change to the contract fails CI until the
snapshot is re-recorded in the same pull request: a changed intent, profile or
posture, widened autonomy, an unprotected path, a narrowed Ruby matrix, a
removed security control, a dropped or relaxed required criterion, a moved
evaluator, a criterion whose command disappeared, or a waiver added, extended,
or given an expiry that cannot be read. A lost command counts even on an optional
check, while dropping that check is benign: a criterion that stays but proves
nothing is a silent hole, where a removed one is a visible decision. Benign
changes — a renamed command, narrowed autonomy, a dropped optional check, a
wider matrix — only show in the drift report, so re-record after those too, or
the snapshot goes stale. Drift recognises one repository across transports only
on github.com, gitlab.com and bitbucket.org; other remotes must match exactly.
The drift step is skipped in forks, whose origin is a different repository.

## What is deliberately not built yet

Each of these was stopped on purpose, not forgotten.

1. **The `submit` rung (§11) — paused until §12 isolation exists.** A design
   was built and reviewed adversarially twice (PR #14, kept open as a draft):
   token from `REANIMATOR_GITHUB_TOKEN`, opt-in by contract and run, split into
   `repair --propose` and `submit`. Both reviews showed that while executed
   checks run as the invoking user, repository code can outlive its command,
   read a later process's token, or rewrite the proposal `submit` trusts.
   Separate processes are not a boundary without user and filesystem
   isolation. Do not wire submission before item 2 is built.
2. **The rest of §12 isolation.** Denied egress is enforced or refused
   (`EgressControl`, ADR-007), but user, filesystem and resource isolation are
   not built: an executed check runs as the invoking user and can write outside
   its disposable copy. `balanced`'s package-registry allowlist is advisory and
   the report says so. Do not let `SECURITY.md` or the README claim more.
3. **Platform work (§03, §18).** GitHub App, web UI, scheduled/continuous runs.
