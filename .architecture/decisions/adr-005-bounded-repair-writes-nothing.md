# ADR-005: Bounded repair proposes, it does not write

- Status: Accepted
- Date: 2026-08-01

## Context

The autonomy ladder (section 11) places `repair` below `submit`: repair
"creates a bounded patch in an isolated workspace" with "no repository write
required until submission." Section 18 keeps automatic merge and broad write
behavior explicitly later, and the product safety floor forbids any layer from
loosening that. So a repair capability that quietly pushed a branch or opened a
PR would violate the spec's own sequencing.

## Decision

`RepairRun` performs the entire repair loop and stops at a **proposed change**:

1. baseline the repository to find a failing required criterion (the obligation),
2. consult `PermissionModel` - if repair is not enabled for the task class, it
   escalates rather than proceeding,
3. route to a ready agent, isolate a workspace copy, and take the agent's patch,
4. reject any patch that touches a protected or out-of-scope path (anti-gaming),
5. apply the patch to a *separate* clean copy and re-verify with Frankenstein's
   own evaluators,
6. only on independent success, materialize a `ProposedChange` (branch, patch,
   title, body) and record a `Run` with outcome `draft_pr`.

`Run#wrote_to_repository?` is a hard `false`. Submitting a proposed change to
GitHub is a separate capability (the `submit` rung) that a human enables
explicitly; it is intentionally not wired here.

## Consequences

- The most eventful thing `frankenstein repair` can do is hand you a verified
  patch and the draft PR it would open - safe to run anywhere, on anything.
- Because verification reuses the same isolated-evaluation path as
  commissioning, a repair cannot pass by editing its own verifier.
- Slice 4's exit ("a patch update can be proposed safely end to end") is met
  while the write boundary stays exactly where the spec draws it.
