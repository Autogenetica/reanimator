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
bundle exec rake                                # specs + StandardRB (expect 232 examples; 1 pending off Linux)
bundle exec exe/reanimator baseline . --execute  # prove this repo on itself
bundle exec exe/reanimator contract .            # resolved contract, incl. security posture
bundle exec exe/reanimator drift . --record      # write .reanimator-snapshot.json
```

Ruby >= 3.3.0. CI exercises 3.3 and 3.4.

## State

0.1.0 is published to RubyGems via trusted publishing (no stored API key); see
`RELEASING.md` for the cut checklist. The README's specification-coverage table
is the authoritative map of what is implemented. Two files still say
"Frankenstein" on purpose: `ADR-006`, which records the rename, and the
changelog note explaining it.

## What is deliberately not built yet

Each of these was stopped on purpose, not forgotten.

1. **The `submit` rung (§11).** `ProposedChange` already produces the draft-PR
   artifact; the write is not wired. Needs an explicit go-ahead plus two
   decisions: the credential scope (per-repo contents + pull-request write), and
   whether submission is per-run opt-in or declared in the contract.
2. **The rest of §12 isolation.** Denied egress is enforced or refused
   (`EgressControl`, ADR-007), but user, filesystem and resource isolation are
   not built: an executed check runs as the invoking user and can write outside
   its disposable copy. `balanced`'s package-registry allowlist is advisory and
   the report says so. Do not let `SECURITY.md` or the README claim more.
3. **Platform work (§03, §18).** GitHub App, web UI, scheduled/continuous runs.
4. **This repo's own security gates.** `reanimator baseline .` reports two
   advisory gaps against itself — no dependency review, no secret scanning. ~20
   lines of CI config, deliberately left as the owner's call because Dependabot
   starts opening pull requests.
5. **A committed self-snapshot.** `reanimator drift --record` would let CI gate
   on this repo's own configuration drift. It was held back while several
   branches were in flight and is now safe to add.
