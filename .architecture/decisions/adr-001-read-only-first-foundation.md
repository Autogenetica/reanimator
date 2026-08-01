# ADR-001: A read-only proof-of-life foundation before autonomy

- Status: Accepted
- Date: 2026-08-01

## Context

The specification is large (20 sections plus appendices) and spans read-only
observation through bounded, agent-driven repair. Its own guidance is emphatic
about sequencing: *"Do not begin with autonomous merge. Begin by making the
repository's definition of life visible, executable, and trustworthy."* The
onboarding promise is that a user gets a trustworthy first vitality report
"without writing configuration, connecting a coding agent, or granting write
permission."

## Decision

The first implementation slice delivers the read-only heartbeat end to end and
nothing that requires write access or an agent:

1. the canonical domain model and effective-policy resolver (Appendix C step 1),
2. inventory + lifecycle classification (delivery slice 1), and
3. discovery + a read-only baseline with proof-of-life reporting (slice 2).

Agent connections, families gates, draft-PR repair, the GitHub App, and the web
UI are deliberately out of scope for this slice, but the domain seams
(`RepositoryMetadata`, `Evaluators`, the policy layers) are shaped so they plug
in without reshaping the core.

## Consequences

- Value lands immediately: `frankenstein baseline` proves a real gem is `ALIVE`
  with zero configuration and zero writes.
- The riskiest capabilities (execution, merge) are gated behind explicit opt-in
  and a safety floor from day one, rather than retrofitted.
- Some spec sections (08, 10–13) are modeled but only partially enforced; the
  README's coverage table states this honestly.
