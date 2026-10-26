# ADR-003: A non-bypassable safety floor, enforced in the resolver

- Status: Accepted
- Date: 2026-08-01

## Context

Section 07 defines a precedence stack whose bottom layer is a *product safety
floor* that "no" higher layer may loosen, and section 09 states the anti-gaming
rule: "a task that modifies the rules of proof cannot use those modified rules
to approve itself." These are described as guarantees, not preferences, so they
must be enforced by code rather than convention.

## Decision

`SafetyFloor` is a module of enforced invariants, and `EffectivePolicyResolver`
applies it last, after owner declarations and discovery:

- Merge autonomy is clamped to `disabled` in v1 regardless of what any layer
  requests, and the clamp is **recorded as a visible note**, never hidden.
- Protected paths (`.reanimator.yml`, `.github/workflows/**`, CODEOWNERS,
  Dependabot config) are always present; a contract may add to the set but the
  union always includes the floor.
- Verifier isolation is a constant (`verifier_isolation? == true`), reflecting
  that grading is separate from any agent workspace.

Owner declarations win over inference (a declared profile/intent beats a guessed
one), but they resolve *within* the floor — the two rules compose in one place.

## Consequences

- The clamp is testable and tested: enabling `merge` in a contract yields
  `:disabled` plus a note.
- When later layers (organization, portfolio, family) are added, they slot into
  the same resolver between the floor and the repository contract without
  changing the enforcement point.
- "Loosening" is a `PolicyViolation`-shaped concept with a home, so future
  layers have a clear contract to honor.
