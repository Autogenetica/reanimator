# ADR-008: Submission is a separate process that ships only the verified tree

- Status: Accepted
- Date: 2026-10-29

## Context

Bounded repair (ADR-005) ends with a `ProposedChange`: a verified patch, a
branch name, a title and a body. Section 11's submit rung turns that into a pull
request. It is the first time Reanimator writes anywhere, so it has to inherit
the invariants rather than bend them: the grader is never the actor, the safety
floor forbids automatic merge, and anything that cannot be confirmed fails
closed.

The owner chose a token from the environment (`REANIMATOR_GITHUB_TOKEN`), so a
GitHub App installation token can be supplied in CI and a fine-grained token
locally, and opt-in by both the contract (`autonomy: submit: allowed`) and the
run.

The first design submitted from inside `repair --submit` and hid the token from
executed checks. Adversarial review broke it, and every point below was
reproduced:

- A check reads the parent's environment (`ps eww`, `/proc/<ppid>/environ`), and
  unsetting a variable does not erase the original environment block, so hiding
  the token from the child protected nothing.
- Verification copied the working tree, so ignored, untracked and skip-worktree
  files could make checks pass that the pull request would not contain.
- From a monorepo subdirectory, root-relative patch paths overwrote a different
  file at the top of the tree.
- A symlinked file was patched through the link locally and replaced by a
  regular file in the pull request.
- A repeat run force-pushed over a reviewer's commits and added commits to a pull
  request a human had marked ready.
- A pull request failure after the branch push was reported as "nothing written",
  and malformed responses raised past the run.

## Decision

- **Two processes, two commands.** `repair --propose FILE` runs repository code
  and never holds the token: `BoundedCommand` refuses to run anything while
  `REANIMATOR_GITHUB_TOKEN` is set. `submit FILE` holds the token, runs no
  repository code and no git, and only calls the GitHub API. The `submit`
  command is the per-run arming; the contract is the ceiling, recorded in the
  proposal and enforced by the submitter.
- **Verify the commit, not the checkout.** `--propose` exports `HEAD` with
  `git archive` and repairs that export, so what is verified is exactly the base
  of the pull request. It refuses anything but a repository root.
- **Ship only what was verified.** The proposal records the base commit, exact
  contents and the committed git mode of each path; symlinks and submodules are
  refused, and `Patch#apply` never writes through a symlink. The submitter
  refuses unless the default branch is still at the recorded base.
- **Never overwrite people.** Reanimator's commits carry a `Generated-by:
  reanimator` trailer. An existing branch is moved only while its tip has it,
  and an open pull request is updated only while it is still a draft.
- **Say what was written.** Every refusal is an outcome with a reason and
  whether a branch was already pushed. Transport and parse failures become
  refusals.
- **Always a draft, never merged.** Elevated review is flagged in the title and
  body; an `:issue`-only task class may not open a pull request.

## Alternatives considered

- **One process, token hidden from children** - the first design. Rejected for
  the reason above: same-user code can read the parent's environment.
- **One process that refuses to execute when the token is set.** Equivalent in
  effect to two steps, with a worse error path; the two-step shape makes the
  boundary visible in the command line and in CI step layout.
- **Local git: branch, commit, push.** Rejected. It writes the working tree the
  tool promises not to touch and needs push credentials where repository hooks
  can see them.
- **Shell out to `gh pr create`.** Rejected. The credential is whatever `gh` is
  logged in as, usually the user's broad personal token.
- **A cleanliness check instead of an export.** Rejected: `git status` cannot
  see ignored or skip-worktree files, and checking before copying races.
- **Fall back to `GITHUB_TOKEN`.** Rejected. A token present for other reasons
  should not silently become a write credential.

## Consequences

- Submitting takes two steps, and in CI the token belongs to the second step
  only.
- Uncommitted work is ignored by `--propose`; commit first to have it verified.
- Proven against a live private sandbox: a draft pull request containing only
  the one-line fix on the verified commit; a repeat run updated the same draft;
  a reviewer's pushed commit and a pull request marked ready were both refused
  and left untouched.
- A GitHub App (Slice 5) can mint installation tokens into the same variable
  for the submit step without changing the submitter.
