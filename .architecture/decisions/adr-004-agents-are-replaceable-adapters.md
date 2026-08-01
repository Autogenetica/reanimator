# ADR-004: Agents are replaceable adapters, proven by isolated commissioning

- Status: Accepted
- Date: 2026-08-01

## Context

Section 08 frames the coding agent as "a replaceable life-force adapter": the
repository's definition of life belongs to its contract, not to whichever
provider performs a repair, and "changing agent providers does not require
redefining acceptance criteria" (section 19 portability). Section 09 adds that
the agent "may attempt the work; it may not grade itself," and the anti-gaming
rule forbids a task from rewriting the rules of proof and passing under them.

## Decision

- Every provider implements one tiny `Agents::Adapter` contract that only
  *enumerates capabilities* and *proposes a repair*. A repair is returned as a
  `Patch` (data), never applied by the agent.
- Commissioning proves a profile ready/degraded/incompatible/unavailable by
  running the six-step test against a **disposable fixture** and grading it with
  Frankenstein's own evaluators. The agent works in one copy; the harness applies
  its patch to a **separate clean copy** and evaluates there — verifier isolation
  is structural, not a convention.
- A patch whose paths are protected or out of scope is refused before it is ever
  applied. That is the anti-gaming rule, enforced.
- The reference `Agents::Local` adapter is a real, deterministic rule-based agent
  (a first-class provider type per section 01). Hosted providers ship as honest
  stubs that report themselves unavailable until connected; a real adapter -
  potentially backed by codenamev/agentic - implements `#repair` behind the same
  contract.

## Consequences

- Commissioning runs end to end today with zero credentials and zero repository
  writes, satisfying the slice-3 exit evidence.
- Because grading never runs in the agent's workspace, promoting a hosted
  provider later cannot weaken verifier integrity.
- Routing (`Routing::Router`) and the permission model (`PermissionModel`) sit
  on top of commissioned profiles, so "which agent" stays an execution concern,
  cleanly separated from "what must be proven."
