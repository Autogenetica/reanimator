# ADR-002: Every discovered fact carries provenance and confidence

- Status: Accepted
- Date: 2026-08-01

## Context

Section 06 is "configuration by confirmation": the product should infer the
majority of a repository contract and ask the user to *confirm facts rather than
transcribe their own CI*. For that to be trustworthy, the UI "must always answer
'Why does Frankenstein believe this?'" and must never let a low-confidence guess
silently become an obligation or authorize an action.

## Decision

`DiscoveredFact` is the single currency of discovery, and it is impossible to
construct one without a `Provenance` (source, extraction method, timestamp) and
a `Confidence`. Detectors only ever emit facts — they never decide policy. A
fact has an explicit review lifecycle (`proposed → accepted/rejected/edited`);
acceptance is what promotes an inference to declared policy.

`Confidence` encodes the section 06 behavior table in code: only `high` is
preselectable, and `low` can shape a question but is not `obligatable?`.

## Consequences

- Reports render "what we found, and why" for free from the fact stream.
- The resolver can reuse detected commands (`bundle exec rspec`) as criteria
  while attributing them to the file that revealed them.
- Adding a detector is additive and cannot, by construction, produce an
  unexplained belief.
