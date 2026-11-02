# ADR-012: A crashed detector blocks the run

- Status: Accepted
- Date: 2026-11-02

## Context

Discovery runs every detector and rescues one that raises, so a single bug
cannot sink the whole observation. Until now the rescue also dropped that
detector's facts as if they had never existed, and every consumer read
"no fact" as "nothing there":

- `support_matrix` read a missing floor as "nothing declared" and credited any
  CI matrix.
- Profile inference read a missing gem or Rails fact as "neither", fell back
  to `generic` - which has no required checks - and a gem whose test suite
  fails read **Alive** and exited 0.
- `drift --record` wrote that shrunken contract down as the new snapshot, and
  `contract --export` printed it as the `.reanimator.yml` to commit, after
  which a declared profile outranks inference for good.

Guarding one evaluator at a time missed the second of these on the first
attempt. Facts are read far from where they are made.

## Decision

Missing is not absent. A detector failure travels with the discovery result,
and it is judged where a verdict is made, not by each consumer:

- `baseline` adds a required `discovery_complete` result with status
  `error` for any failure. It is appended after waivers, so none can cover
  it, and a declared check may not take its id. The run cannot be Alive, and
  it escalates with exit 2 through every surface results already reach.
- A contract read in part is never written down: snapshots (`drift`,
  `drift --record`) and `contract --export` refuse with exit 1.
- `repair` stops safely before proposing anything against it.
- `discover` lists the failure under "not read".

Inputs that made detectors raise without being a reason to block - a
directory where a file was expected, a `package.json` that is not an object,
a workflow `strategy` written as one expression, a `.nan` in a matrix - are
fixed in the detectors, so the block is kept for genuine bugs and unreadable
files.

## Alternatives considered

- **Block only for detectors whose facts feed the contract.** Today the
  Relationships and OperationalProof facts feed no criterion, profile, intent
  or snapshot field, so a crash in either changes no obligation, and blocking
  on it is a CI failure with no recourse but a fix to Reanimator. Rejected for
  now: whether a detector "feeds the contract" is a property of every
  consumer, not of the detector, and it changes silently the first time
  someone reads one of those facts. The detector bugs reviewers found were
  fixed instead. If a false block proves costly in practice, this is the
  alternative to revisit, with each detector declaring what it feeds and a
  spec that fails when an undeclared fact is read.
- **Let a waiver cover `discovery_complete`.** Rejected: a waiver accepts a
  known risk for a stated reason and an expiry; a crash is not a known risk,
  and the waiver would outlive the bug it hid.
- **Raise, and let the whole run fail.** Exit 1 everywhere, and the simplest
  rule. Rejected for `baseline` and `discover`, where the rest of the report is
  still worth reading and a required error already blocks; kept for snapshots
  and export, which would otherwise write the partial contract down.
- **Keep dropping facts, log louder.** The previous behaviour. A warning on
  stderr beside a green result is still a green result.
