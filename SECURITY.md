# Security Policy

Security is part of Reanimator's design, not a hidden settings page. The tool
treats repository content, issues, logs, pull requests, and external
documentation as **untrusted input**, and treats coding-agent responses as
**untrusted proposals** until they are independently evaluated.

## Reporting a vulnerability

Please report suspected vulnerabilities privately to **v@codenamev.com** rather
than opening a public issue. Include a description, reproduction steps, and the
affected version. You will receive an acknowledgement, and a coordinated fix and
disclosure timeline.

## Design guarantees relevant to security

- **Read-only by default.** Inventory, classification, discovery, and baseline
  require no write permission and never modify repository source.
- **Disposable-workspace execution.** When checks execute, they run inside a
  throwaway copy of the repository, never the original working tree, so a build
  or test cannot mutate the real checkout (no stray artifacts).
- **Bounded execution.** Any executed check is opt-in (per run and globally) and
  runs under a hard wall-clock bound that terminates the entire process group,
  so a spawned child cannot outlive the bound.
- **Network egress follows the posture.** Under `strict` and `local`, which deny
  egress, executed checks run inside an empty network namespace (unprivileged
  `unshare` on Linux), leaving only loopback. Where that cannot be enforced — macOS,
  or Linux without unprivileged user namespaces — Reanimator refuses to execute
  and says why, rather than running unprotected. GitHub-hosted Ubuntu 24.04
  runners restrict these namespaces by default; run
  `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` before
  Reanimator to enforce rather than refuse. Under `balanced` the network is
  not restricted: its package-registry allowlist is advisory, and every executed
  baseline says so.
- **Known limitation.** User, filesystem, and resource isolation (spec section 12)
  are planned but not implemented: an executed check runs as the invoking user and
  can write outside its disposable copy. Treat `--execute` on untrusted
  repositories accordingly; it is off by default.
- **The submission token stays with the submitter.** `REANIMATOR_GITHUB_TOKEN`
  is read only by `Submitter`, never by an agent, and it is withheld from every
  command a check executes, because repository code is untrusted. Submission
  opens a draft pull request through the GitHub API and never writes to the
  local working tree; merge stays a human decision.
- **Non-bypassable safety floor.** No configuration layer may loosen verifier
  isolation, remove protected paths (`.reanimator.yml`, workflows, CODEOWNERS),
  or enable automatic merge in v1.
- **Anti-gaming.** A task that modifies the rules of proof cannot use those
  modified rules to approve itself.
