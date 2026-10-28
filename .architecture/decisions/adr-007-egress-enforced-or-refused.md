# ADR-007: Network egress is enforced or execution is refused

- Status: Accepted
- Date: 2026-10-28

## Context

`SecurityPosture#network` answered `:deny` for `strict` and `local`,
`:package_registries` for `balanced`, and `:custom` for `custom` - and nothing
consumed it. `BoundedCommand` bounded wall-clock time and `Isolation` bounded
the working tree; neither touched the network. A repository under `strict`
could run `--execute` and have its checks reach the internet while the posture
it had chosen said they could not. That is the shape of defect this codebase
treats most seriously: a promise that reads as kept while nothing keeps it.

Every executed command passes through one place, `BoundedCommand`, reached from
three callers: `BaselineRunner` (via `Evaluators::Command`), `Family::GateRunner`,
and `RepairRun` (through its baselines).

## Decision

`EgressControl` turns the posture's network rule into one of three decisions,
and every execution path obeys it:

- **Denied.** For `:deny`, each command runs behind an unprivileged
  `unshare --user --map-current-user --net` prefix (falling back to
  `--map-root-user` on older util-linux). The prefix is trusted only after a
  probe shows the namespace holds nothing but loopback, read from the process's
  own `/proc/net/dev`.
- **Refused.** For `:deny` where no such prefix works - macOS, or Linux that
  restricts unprivileged user namespaces - nothing executes. Command criteria
  are `skipped` with the reason, and the report's `Mode:` line says the run did
  not execute and why.
- **Unrestricted, and said so.** `balanced` and `custom` run as before, and the
  `Mode:` line states that the network is not restricted.

Two consequences follow from fail-closed:

- `RepairRun` stops safely when its baseline did not execute. A refused
  baseline has no *failed* criteria, and reading that as "all required criteria
  pass" would turn a refusal into a clean bill of health.
- A family gate runs under the downstream member's posture, and a member whose
  contract cannot be resolved is held to `strict`.

The decision is made lazily, only when execution is requested, because probing
spawns a process and a read-only baseline promises never to.

## Alternatives considered

- **A cross-platform sandbox.** Network namespaces on Linux, `sandbox-exec` on
  macOS, or a container runtime everywhere. Rejected: `sandbox-exec` is
  deprecated, and a container runtime becomes a dependency of a tool whose
  default promises to change nothing. Refusal costs nothing and is honest; real
  enforcement was added only where the kernel offers it unprivileged.
- **Warn and run anyway.** Rejected outright. A warning beside a green result is
  still a green result, and the repository would read as proven under a posture
  it never ran under.
- **Report a refused command as `error` rather than `skipped`.** Both count as
  unproven, so either keeps the state honest. `error` means an evaluator could
  not decide; here the boundary decided, which is what `skipped` already
  means for unavailable evaluators.
- **Gate refusal in `BaselineRunner#execution_allowed?`,** as the build plan
  first suggested. Rejected because commands would then read `planned` ("would
  run"), which hides that execution was requested and refused. Refusal is
  visible per criterion and on the `Mode:` line instead.
- **Enforce `balanced`'s package-registry allowlist.** That needs an egress
  proxy with per-ecosystem host lists. Out of scope; the report says the
  allowlist is advisory rather than implying it holds.
- **Trust `unshare` exiting zero.** Rejected in favour of checking the
  namespace's interfaces, so a wrapper that runs but isolates nothing is not
  mistaken for enforcement.

## Consequences

- On macOS a `strict` or `local` repository cannot execute checks. That is the
  intended, visible boundary.
- GitHub-hosted Ubuntu 24.04 runners restrict unprivileged user namespaces
  through AppArmor, so `strict` refuses there unless the workflow first runs
  `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`. This
  repository's CI does, so the real-namespace spec runs instead of reporting
  pending; `SECURITY.md` tells users the same.
- User, filesystem and resource isolation remain unimplemented. An executed
  check runs as the invoking user and can write outside its disposable copy;
  `SECURITY.md` keeps that as a known limitation.
