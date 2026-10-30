# ADR-009: Escalations surface through exit status and the CI run

- Status: Accepted
- Date: 2026-10-29

## Context

Section 16 escalation existed as data and went nowhere. `Run` had an
`:escalation` outcome, `RepositoryState` had `needs_you`, and the specification's
own example - "the project declares Ruby 3.2 support but CI no longer tests
it" - was meant to be caught by `Evaluators::SupportMatrix`. Every command still
exited 0 whatever it found, so in CI an at-risk repository looked identical to
a healthy one unless someone read the log.

The owner chose the cheapest surface that needs no platform work: exit codes
plus the check output already rendered by `Reports::GitHubCheck`.

Writing this slice also showed that `SupportMatrix` did not catch its own
example. It credited any CI Ruby matrix, so a gem declaring `>= 3.1` while CI
tested only 3.3 and 3.4 read as verified.

## Decision

- **Exit status separates the tool from the repository.** `1` stays "Reanimator
  could not do its job" - including a portfolio path it could not read, because
  "we could not tell" is never a pass - and `drift` needing review, unchanged.
  `2` means it did its job and a human is needed.
- **What needs a human is defined once, on the subjects themselves,** as
  `Finding`s (level, title, message). Annotations and summaries consume
  findings and never ask which kind of subject produced them.
  - `Baseline#escalations`: required criteria that failed or are unproven.
    `planned` is excluded only when the run did not ask to execute; when it
    asked and execution was withheld, planned checks escalate too.
  - `Run#needs_attention?`: every outcome except a healthy no-op. A draft PR
    counts: a verified change that exists only as output needs someone to
    submit or review it. A repair that finds nothing failed while something is
    unproven escalates instead of calling the repository healthy.
- **Advisory problems are visible but never block.** `Baseline#advisories`
  (non-required criteria that failed, lack evidence, or errored) become
  `::notice` annotations, which GitHub caps separately from errors and warnings;
  blocking findings become `::error`. A repository that wants a criterion to
  block declares it required in `.reanimator.yml`.
- **Repository text cannot drive the CI surface.** Reports quote claims,
  details and reasons the repository controls, so inside Actions they are
  printed between `::stop-commands::` markers with a fresh random token, and
  the job summary's fence is longer than any backtick run it contains.
  `--format json` prints pure JSON - JSON escapes newlines, so no line can start
  a command - and skips annotations. A summary that cannot be written is
  reported, not raised.
- **`SupportMatrix` compares the declared floor with CI's lowest released
  Ruby across every workflow,** per minor release. A matrix above the floor,
  or one exercising no released Ruby, is `missing_evidence`.

## Alternatives considered

- **Fail on any unresolved required criterion, including `planned`.** Rejected:
  a read-only baseline would always exit non-zero, making the safe default look
  broken and teaching people to ignore the signal.
- **Fail on advisory problems too.** Rejected: advisory would stop meaning
  advisory, and every balanced repository missing an optional control would go
  red.
- **Make `support_matrix` required in the gem profiles.** Rejected for now: it
  would change the state of every gem without a CI Ruby matrix. The contract
  already lets an owner opt in, which is the precedence stack doing its job.
- **Open a GitHub issue per escalation.** Considered and deferred. It needs the
  submit credential and deduplication state, and the owner chose the surface
  that needs neither.
- **Change `drift`'s exit status to 2.** Deferred. It already exits 1 for
  "requires review", and changing a published contract belongs in its own
  change.

## Consequences

- `baseline`, `portfolio` and `repair` can now fail a CI job. That is the point,
  and it is a behaviour change from 0.1.0, recorded in the changelog.
- Non-duplication within a run is structural: one annotation per finding. Across
  runs there is nothing persistent to duplicate, because no issue is opened.
- Adversarial review found the first version exited 0 for a repair "no-op" on
  an unproven repository, for withheld execution and for unreadable portfolio
  paths; broke `--format json` in Actions; let repository text emit
  `::stop-commands::` and silence the real annotations; and mis-graded support
  matrices split across jobs or written as arrays. Each is now pinned by a spec,
  and each surviving mutant the review found now fails one.
- The build plan claimed `SupportMatrix` already detected narrowed support; it
  did not, and now does.
