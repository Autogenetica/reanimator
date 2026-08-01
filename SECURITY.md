# Security Policy

Security is part of Frankenstein's design, not a hidden settings page. The tool
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
- **Bounded execution.** Any executed check runs under a hard wall-clock bound
  and is opt-in per run and globally.
- **Non-bypassable safety floor.** No configuration layer may loosen verifier
  isolation, remove protected paths (`.frankenstein.yml`, workflows, CODEOWNERS),
  or enable automatic merge in v1.
- **Anti-gaming.** A task that modifies the rules of proof cannot use those
  modified rules to approve itself.
