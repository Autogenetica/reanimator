# ADR-010: Confine executed checks to their workspace (proposed)

- Status: Proposed — needs the owner's decisions below before it is built
- Date: 2026-10-30

## Context

Specification section 12 asks for user, filesystem and resource isolation of
executed checks. Only network egress is built (ADR-007). Today an executed
check runs as the invoking user, can read anything that user can, can write
outside its disposable copy, and can leave processes running after
`BoundedCommand` returns (the process group is killed only on timeout).

That gap is why the submit rung is paused. PR #14 split submission into
`repair --propose` and `submit` so the GitHub token never shares a process with
repository code. Two adversarial reviews showed that is not a boundary while
checks run unconfined: a check started a background process that outlived
`repair --propose`, then rewrote the proposal file and read a later process's
token from `/proc/<pid>/environ`. Every boundary Reanimator wants - the token,
the proposal, the original checkout - depends on the check being unable to
reach it.

## Evidence

On Linux, an unprivileged user can already confine a command this way, with
the same `unshare` that ADR-007 uses for the network. In a stock `ruby:3.3`
container, as an ordinary user, with unprivileged user namespaces allowed
(as on GitHub-hosted runners after the `sysctl` ADR-007 documents):

```
unshare --user --map-root-user --mount --net sh -c '
  mount --bind "$WS" "$WS"            # keep the workspace writable
  mount -o remount,bind,ro /          # everything else read-only
  mount -t tmpfs tmpfs /tmp           # private scratch space
  ...'
```

- A write into the workspace succeeded.
- A write to `$HOME` failed with "Read-only file system", and nothing appeared
  outside afterwards.
- `/tmp` was private: a file written there did not exist outside.
- Reads were *not* confined: a file in `$HOME` was still readable. Masking has
  to be explicit.

`--map-root-user` is required: with `--map-current-user` the mounts are
refused. The process is root only inside its own namespace.

Leftover processes, the second half of the PR #14 attack, end with a PID
namespace. A command that started `(sleep 30 &)` and exited left the `sleep`
running without one; under `unshare --user --map-root-user --pid --fork
--kill-child` it was gone as soon as the command ended, because the kernel
kills every process in a PID namespace when its first process exits. No
`/proc` remount is needed for that.

## Proposed design

`BoundedCommand` gains a confinement prefix alongside the egress prefix, built
the same way: probed once, trusted only after the probe proves the property,
and refused - never silently skipped - where it cannot be had.

1. **Filesystem.** A new mount namespace with the root re-mounted read-only;
   the disposable workspace bind-mounted read-write; a private tmpfs on
   `/tmp`, `/var/tmp` and `/dev/shm`; and tmpfs masks over `$HOME` (with
   bundler and gem caches bind-mounted read-only so `bundle exec` works) and
   any path the contract or configuration names as secret.
2. **Processes.** A PID namespace (`--pid --fork --kill-child`), so when the
   command ends every process it started ends with it - no daemon survives to
   reach a later step. Shown above; no `/proc` remount required.
3. **Resources.** `setrlimit` on CPU time, address space, open files and
   process count, from configuration with conservative defaults. Portable,
   and useful on macOS too.
4. **Proof.** The probe checks each property - a write outside the workspace
   fails, `$HOME` is empty, a background process does not outlive the command -
   the way ADR-007's probe checks for loopback only.
5. **Refusal.** Where confinement is required and cannot be proven (macOS;
   Linux without unprivileged user namespaces), execution is refused with the
   reason, exactly as ADR-007 refuses unenforceable egress.

With this in place the submit rung can resume from PR #14: `repair --propose`
runs confined, so nothing it executes can outlive it, rewrite the proposal, or
read the submit step's token.

## Decisions needed from the owner

1. **Which postures require confinement?** Options: `strict` and `local` only
   (mirrors egress; `balanced` users keep today's behaviour); or every posture
   whenever `--execute` is given (safest, but macOS could then execute nothing).
2. **macOS.** Refuse where required (consistent with egress), or offer a
   documented, weaker mode (e.g. `sandbox-exec`, which is deprecated)?
3. **What counts as secret beyond `$HOME`?** A fixed list, a contract key, or
   both?
4. **Resource defaults.** Values for CPU seconds, memory and process count, and
   whether exceeding them is a failure or an error.
5. **Resume the submit rung** once confinement is in place, under which
   postures?

## Alternatives considered

- **Containers (Docker, Podman).** Strong isolation, but a runtime dependency
  for a tool whose default promises to change nothing, and unavailable in many
  CI and developer setups. Rejected for the same reason as in ADR-007.
- **bubblewrap (`bwrap`).** Does exactly this, well, but is another binary to
  install; the namespaces it uses are reachable directly with `unshare`, which
  egress control already depends on. Worth reconsidering if the hand-built
  mount sequence grows.
- **Separate CI jobs only.** Moving `submit` to a separate job (separate VM)
  protects the token in CI, and the PR #14 design should still document it,
  but it does not protect a developer's machine or the original checkout.
