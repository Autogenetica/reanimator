# Build plan: completing the specification

Point a session at this file to pick up the build. It is the state of play, the
remaining work as executable slices, and the traps worth knowing before you
start. `CLAUDE.md` has the working agreements and is not repeated here.

**One caveat, stated up front.** The original specification was supplied as a
`.docx` and is no longer available to the session that wrote this. Everything
below is reconstructed from the implementation, the ADRs, and the
specification-coverage table in `README.md`. Where this file and the actual
specification disagree, **the specification wins** — re-supply it to the session
that continues this work. Section numbers below are the ones the code itself
cites in its comments, so they are reliable as cross-references even where the
prose summary of a section is approximate.

## The system in one page

One pipeline, each stage a value object that the next stage consumes:

```
Repository            a path on disk, read-only helpers
  → Discovery         Detectors::* emit DiscoveredFact (+ Provenance, Confidence)
  → Classifier        suggests a LifecycleIntent; Portfolio/Cohort group many
  → EffectivePolicyResolver
                      intent + VitalityProfile + .reanimator.yml + SafetyFloor
                      → EffectiveContract (criteria, posture, autonomy, waivers)
  → BaselineRunner    Evaluators::* grade each AcceptanceCriterion
                      → Baseline + ProofOfLife → RepositoryState
  → RepairRun         bounded, agent-assisted, writes nothing
                      → Run (outcome: no_op/report/draft_pr/escalation/safe_stop)
```

Crosscutting: `CriteriaStack` merges the layers that contribute obligations.
`ContractSnapshot` + `DriftDetector` + `SnapshotStore` + `PortfolioDrift` detect
configuration drift. `Family*` handles cross-repository compatibility gates.
`PermissionModel` resolves what an agent may do. `Reports::*` render everything
as plain text with no colour or TTY dependency, which is why they are trivially
testable. `CLI` is a thin Thor shell over module methods on `Reanimator`.

Four invariants hold the design together. Breaking any of them is an ADR, not a
patch:

1. **The grader is never the actor.** An agent proposes; `Evaluators::*` decide.
   An acting agent cannot reach the effective contract, the hidden tests, or the
   baseline evidence.
2. **The safety floor cannot be loosened** by any layer above it
   (`SafetyFloor`): protected paths, verifier isolation, no automatic merge in
   v1.
3. **Anti-gaming**: a task that modifies the rules of proof cannot use the
   modified rules to approve itself.
4. **Read-only by default**, and execution is doubly gated — per-run `execute`
   plus global `allow_execution` — and even then runs in a disposable copy.

## Section status

| § | Area | State |
| --- | --- | --- |
| 00–02 | Model, goals, constraints | done |
| 03 | Onboarding stages | CLI stages done; **GitHub App / web UI not built** |
| 04–05 | Portfolio intake, lifecycle intent | done |
| 06 | Discovery by confirmation, drift | done, incl. portfolio drift |
| 07 | Configuration & precedence | done |
| 08 | Agent connections, commissioning, routing | done |
| 09 | Acceptance criteria, verifier isolation, waivers | done |
| 10 | Repository families & compatibility graphs | done |
| 11 | Autonomy ladder & permission model | ladder done; **`submit` rung not wired** |
| 12 | Security controls | done — denied egress enforced on Linux, refused elsewhere (Slice 1) |
| 13/17 | Bounded repair & run ledger | done (no writes) |
| 14–15 | Baseline & proof-of-life | done |
| 16 | Escalation | done — exit status 2 + Actions annotations/summary (Slice 3) |
| 18 | MVP slices 1–4 | done |
| 19 | Portability | satisfied by ADR-004 (agents as replaceable adapters) |
| 20 | v1 defaults | done (autonomy defaults, posture defaults, Ruby/Rails first) |

Slices 1 and 3 are done; Slice 2 (submit) is paused and the rest remain. They are ordered by how much the rest
depends on them.

---

## Slice 1 — Enforce what the security posture promises (§12) — done

**Outcome (2026-10-28).** `EgressControl` turns `SecurityPosture#network` into
a decision consumed by every execution path (`BaselineRunner` → `Evaluators::Command`,
`Family::GateRunner`, and `RepairRun` through its baselines):

- `:deny` (`strict`, `local`): commands run behind an unprivileged
  `unshare --user --map-current-user --net` prefix (falling back to
  `--map-root-user`), probed once per process and accepted only if the
  namespace really shows nothing but loopback. Proven in a Linux container: an
  outbound connection succeeds without the prefix and cannot resolve with it.
- No namespace support (macOS; Linux without unprivileged user namespaces): the
  baseline refuses. Command criteria are `skipped` with the reason, `Mode:` says
  "not executed — …", and nothing runs.
- `balanced` / `custom`: unrestricted, and the `Mode:` line says so — the
  registry allowlist is advisory. Enforcing it would need an egress proxy.
- `RepairRun` now stops safely when its baseline did not execute, instead of
  reading zero failures as "all required criteria pass".

Not done, and still listed in `SECURITY.md`: user, filesystem and resource
isolation. An executed check runs as the invoking user and can write outside
its disposable copy.

The original brief follows.


**The gap.** `SecurityPosture#network` returns `:deny`, `:package_registries`
or `:custom`, and **nothing consumes it**. `BoundedCommand` bounds wall-clock
time and kills the process group; `Isolation` bounds the working tree. Neither
bounds the network. So a `strict` or `local` posture currently promises
deny-by-default egress and does not deliver it. `SECURITY.md` admits this under
"Known limitation" and the README coverage table says "network egress still
advisory".

**Do not close this by building a cross-platform sandbox.** That is a large,
OS-specific project (Linux network namespaces, macOS `sandbox-exec` which is
deprecated, or a container runtime you then depend on). The honest increment is
smaller and more in keeping with the rest of the system:

> When the posture demands egress control and the runtime cannot prove it is
> enforcing it, **refuse to execute** rather than executing unprotected.

That is the same fail-closed rule the codebase already applies to unreadable
snapshots and expired waivers, and it converts a silent lie into a visible,
actionable boundary. A `skipped` or `error` criterion result saying "this
posture requires denied egress and this runner cannot enforce it" is strictly
better than a pass that was never protected.

**Where.** `BoundedCommand` (the execution boundary), `BaselineRunner`
(`execution_allowed?` already gates on two conditions — this is a third),
`SecurityPosture#network` (the value to consume), `SECURITY.md` and the README
coverage row (update the honest-limitation text **only** when it becomes true).

**Then, optionally,** add real enforcement behind a capability check: detect
`unshare`/netns availability on Linux and run under it, keeping the refusal as
the fallback everywhere else.

**Done when** a `strict`-posture repository with `--execute` either runs with
egress actually denied, or refuses and says why — and never silently runs
unprotected. Prove it by running the CLI, not just the suite.

---

## Slice 2 — Wire the `submit` rung (§11)

**The gap.** The artifact exists and the write does not. `ProposedChange`
produces the draft-PR body; `Run::OUTCOMES` includes `:draft_pr`; `RepairRun`
reaches that outcome; `PermissionModel` already clamps `submit` against the
contract and `SafetyFloor` already forces `merge: :disabled` in v1. Nothing
calls GitHub.

**Two decisions are required before writing code**, and they are the owner's,
not the implementer's:

1. **Credential scope.** Minimum viable is per-repository `contents: write` plus
   `pull_requests: write`. Decide whether that is a GitHub App installation
   token (preferred — scoped, short-lived, auditable) or a PAT.
2. **Opt-in shape.** Is submission enabled per run (`--submit`), or declared in
   `.reanimator.yml` under `autonomy: submit:`? The autonomy ladder implies the
   contract; operational caution implies the flag. Both is defensible: the
   contract sets the ceiling, the flag arms it for one run.

**Design constraints that fall out of the existing invariants:**

- The submitter must be **a separate component from the agent**, mirroring
  verifier isolation. The acting agent must never hold the credential — it
  proposes a patch, and something else decides whether to submit it.
- A change touching a protected path (`.reanimator.yml`, workflows, CODEOWNERS,
  Dependabot config) carries `risk_class: :elevated` and must land as a draft
  with elevated review, never auto-ready.
- The anti-gaming rule bites here: a change that edits the verifier definitions
  cannot be validated by the edited verifier. Check `EffectiveContract#verifier_criteria`
  before submitting.
- Draft, always, in v1. `merge` stays `:disabled` at the floor.

**Where.** A new submitter class (not inside `Agents::*`), `RepairRun` to call
it, `Run` to record the real PR URL, `CLI#repair` for the flag,
`EffectivePolicyResolver`/`ContractFile` if the contract gains a key.

**Done when** a bounded repair on a fixture repository produces a real draft PR
with the `ProposedChange` body, and a repository that has not enabled `submit`
still reaches `:escalation` instead. **Never let the suite submit anything** —
the submitter needs a dry-run seam the specs use.

---

## Slice 3 — Give escalation somewhere to go (§16) — done

**Outcome (2026-10-29).** Decisions: exit status plus check output, no platform
work; a draft waiting to be submitted counts as needing a human; advisory
problems are `::notice`. `baseline`, `portfolio`, `repair` and `submit` exit `2`
when a human is needed (`Finding`s from `Baseline` and `Run`), keeping `1` for
the tool failing. Inside GitHub Actions, `ActionsSurface` prints one annotation
per finding and appends the check to the job summary, with reports fenced off
by `::stop-commands::` so repository text cannot forge or silence annotations. **Correction to the brief below:** `SupportMatrix` did
*not* detect narrowed support — it credited any CI matrix. It now compares the
declared floor with CI's lowest Ruby. See ADR-009.

The original brief follows.


**The gap.** `Run::OUTCOMES` has `:escalation`, `Reports::Run` renders it, and
`RepositoryState` has `needs_you`. Nothing tells a human. The specification's
own example — "the project declares Ruby 3.2 support but CI no longer tests it"
— is already *detected* by `Evaluators::SupportMatrix`, and then goes nowhere
but stdout.

**Decision needed:** the delivery surface. Candidates, cheapest first: exit
codes plus `Reports::GitHubCheck` output in CI (already built, needs wiring); a
GitHub check-run annotation; an issue opened once per distinct escalation and
updated rather than duplicated; a digest for a portfolio.

Prefer whichever does not require the platform work in Slice 5. The exit-code
and check-output path is available today.

**Done when** a repository whose declared support has silently narrowed causes a
visible, non-duplicating escalation in CI without anyone reading a terminal.

---

## Slice 4 — Make the tool steward itself (self-hosting)

Two small items, both deliberately deferred rather than forgotten, and both now
unblocked:

- **Commit a self-snapshot.** `reanimator drift --record` writes
  `.reanimator-snapshot.json`; committing it lets CI gate on this repo's own
  configuration drift. Held back while several branches were in flight.
- **Close the repo's own two advisory security gaps.** `reanimator baseline .`
  reports no dependency review and no secret scanning against itself. Roughly 20
  lines of CI config. Left as the owner's call because Dependabot begins opening
  pull requests the moment it lands.

Both are worth doing because they make the tool's own repository the first
honest demonstration of it. Add a `drift` step to `main.yml` once the snapshot
is committed.

---

## Slice 5 — Platform (§03, §18)

GitHub App, web UI, scheduled/continuous runs. Explicitly later in the
specification, and the largest remaining piece. `Reports::GitHubCheck` already
renders the §15 check surface, so the *output* contract exists; what is missing
is the app that posts it, the hosting, and the contract-review UI the §07
precedence stack was designed to feed.

Do not start this before Slices 1–3. All three change what the platform would
have to display.

---

## Traps

- **`Reports::Snapshot` and `Reports::Drift` take the re-record command as a
  string** (`record_with:`), supplied by `SnapshotStore#record_command`. The
  store is the only thing that knows where snapshots live, so it is the only
  thing that knows how to tell someone to put one back. Don't reassemble that
  command at a call site.
- **`CriterionResult#unproven?` includes `:error` on purpose.** An evaluator
  that could not decide is not a pass. If you add a status, decide explicitly
  which side of that line it falls on; getting it wrong makes a broken check
  read green, which has already happened once here.
- **`DriftDetector` refuses to compare snapshots from different repositories.**
  Fixture specs that build two lookalike temp repos will be correctly rejected —
  edit one repository in place instead.
- **`ContractSnapshot` deep-freezes copies**, not the caller's collections, so
  recording a contract never freezes the live one.
- **Profile criteria are defaults.** Discovery substitutes the commands a
  repository actually uses; anything a profile expects but discovery cannot find
  is surfaced as missing proof, never assumed.
- **`EgressControl.namespace_prefix` is probed once per process and memoized.**
  Specs stub it rather than depend on the host; the one spec that exercises
  real namespaces reports *pending* off Linux, so a green run never hides that
  enforcement went untested. A read-only baseline must never probe — that would
  spawn a process — so the decision is made lazily, only when execution is requested.
- **A rename touches ~150 files.** Do it as a re-runnable substitution script,
  not a hand-made diff, and land it last — `ADR-006` records why.

## Verifying you have not broken anything

```bash
bundle exec rake                                  # 257 examples (1 pending off Linux), StandardRB
bundle exec exe/reanimator baseline . --execute    # ALIVE — 100% (3/3)
bundle exec exe/reanimator contract .              # posture, criteria, protected paths
bundle exec exe/reanimator drift .                 # obligations, or drift if recorded
```

The suite is necessary and not sufficient. Most defects in this codebase were
found by reading real CLI output against a fixture repository, so do that before
claiming a slice works.
