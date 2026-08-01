# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Canonical domain model: lifecycle intent, vitality profiles (Ruby-first),
  discovered facts with provenance and confidence, acceptance criteria, and the
  proof-of-life state vocabulary.
- Read-only discovery with detectors for Bundler, Ruby gems, Rails apps,
  discovered commands, GitHub Actions (CI matrix + security controls),
  repository security controls, forks, operational proof, and relationships.
- Portfolio intake: cohort classification and a recommended onboarding set that
  never preselects everything.
- `EffectivePolicyResolver` and a non-bypassable `SafetyFloor` implementing the
  section 07 precedence rules (owner declaration wins; nothing loosens the
  floor; merge disabled in v1).
- `.frankenstein.yml` reader/writer with lossless round-trip.
- Baseline runner with isolated evaluators (command, http-smoke, repository
  integrity, documentation, support matrix), bounded/opt-in execution, and
  proof-of-life assessment.
- Reporters mirroring the specification artifacts: the GitHub Check surface, the
  full baseline report, the Appendix A portfolio baseline, discovery, contract,
  and inventory.
- A Thor CLI (`frankenstein inventory|discover|contract|baseline|portfolio`).
