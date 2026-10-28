# ADR-008: Submission is a separate component that ships only the verified tree

- Status: Accepted
- Date: 2026-10-28

## Context

Bounded repair (ADR-005) ends with a `ProposedChange`: a verified patch, a
branch name, a title and a body. Section 11's submit rung turns that into a pull
request. It is the first time Reanimator writes anywhere, so it has to inherit
the invariants rather than bend them: the grader is never the actor, the safety
floor forbids automatic merge, and anything that cannot be confirmed fails
closed.

The owner settled two questions before implementation began:

- **Credential:** a token from the environment (`REANIMATOR_GITHUB_TOKEN`), so a
  GitHub App installation token can be supplied in CI and a fine-grained token
  locally, without building App authentication yet.
- **Opt-in:** both. The contract's `autonomy: submit: allowed` is the ceiling;
  `repair --submit` arms it for one run.

## Decision

- **A `Submitter`, outside `Agents::*`, is the only reader of the token.** It
  mirrors verifier isolation: the agent proposes, something else decides
  whether the proposal leaves the machine. `BoundedCommand` withholds the token
  from every command a check runs, because those commands are repository
  code - untrusted input.
- **The pull request is built through the GitHub API, not local git.** Tree,
  commit, branch and pull request are created remotely. Nothing is written to
  the local working tree, so "repair never writes the checkout" still holds.
- **Only the verified tree ships.** The repair is verified against the local
  checkout, so the submitter refuses unless that checkout is clean and its HEAD
  *is* the remote default branch's head. The commit's parent is that head. A
  pull request built on any other base would carry changes nobody verified.
- **Idempotent by construction.** `ProposedChange#branch` is deterministic, so
  a repeat run force-moves the same `reanimator/…` branch and updates the open
  pull request instead of opening another.
- **Always a draft, never merged.** Elevated review - a contract with verifier
  criteria, or a task class whose submit policy is `draft_elevated` - is flagged
  in the title and body. A task class whose policy is `:issue` may not open a
  pull request at all.
- **Every refusal escalates with the change attached.** Contract not enabled,
  no token, a dirty or diverged checkout, GitHub saying no: each becomes an
  `escalation` run carrying the verified `ProposedChange`, so the work is not
  lost and a human can pick it up.

## Alternatives considered

- **Local git: create a branch, commit, push.** Rejected. It writes the working
  tree and branch list the tool promises not to touch, needs push credentials
  in the git layer where repository hooks can see them, and depends on the
  user's git configuration.
- **Shell out to `gh pr create`.** Rejected. The credential is whatever `gh` is
  logged in as - usually the user's broad personal token - which cannot be
  scoped to the submit rung or audited as Reanimator's.
- **Submit on top of the remote head whatever the local state.** Rejected. The
  patch holds whole-file contents verified against the local tree; applied to a
  different base, it can silently revert newer changes in the same files.
- **Raise on submission failure.** Rejected: an exception loses the verified
  change. A run with an `escalation` outcome keeps it.
- **Fall back to `GITHUB_TOKEN`.** Rejected. A token present for other reasons
  should not silently become a write credential; the dedicated variable is the
  opt-in.

## Consequences

- Submission needs a clean checkout at the default branch's head. Repairing a
  feature branch, or a checkout with local edits, escalates rather than submits.
- `Run#wrote_to_repository?` is now true exactly when a pull request was
  opened, and the run report says what was written and what was not.
- Proven against a live private repository: a draft pull request containing
  only the one-line fix, its commit parented on the verified head, and a repeat
  run that updated the same pull request.
- A GitHub App (Slice 5) can mint installation tokens into the same
  environment variable without changing the submitter.
