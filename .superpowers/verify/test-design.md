# Verification test-design checklist
# (PROJECTION of test-design.json — the JSON is the source of truth; do not hand-edit this file)

## SPR-BUILD-06
- acceptance.then: only S4_BUILD executor may become external after explicit confirmation
- [ ] technique: BVA
- [ ] technique: decision-table
- [ ] technique: error-guessing
- [ ] technique: pairwise
- [ ] technique: use-case

## SPR-CURRENT-04
- acceptance.then: Claude and Codex active installs resolve through stable current pointers after pinning
- [ ] technique: BVA
- [ ] technique: decision-table
- [ ] technique: error-guessing
- [ ] technique: pairwise
- [ ] technique: use-case

## SPR-ENTRY-01
- acceptance.then: entry recap names S0 through S6, maps stages to skills, states current state/action, and uses natural language rather than boilerplate
- [ ] technique: BVA
- [ ] technique: decision-table
- [ ] technique: error-guessing
- [ ] technique: pairwise
- [ ] technique: use-case

## SPR-ENTRY-02
- acceptance.then: entry behavior keeps the session in S0_DISCUSS until material unknowns are resolved
- [ ] technique: BVA
- [ ] technique: decision-table
- [ ] technique: error-guessing
- [ ] technique: pairwise
- [ ] technique: use-case

## SPR-FEEDBACK-07
- acceptance.then: verification misses are recorded as structured checklist or archetype feedback and unresolved P2/P3 blocks signoff
- [ ] technique: BVA
- [ ] technique: decision-table
- [ ] technique: error-guessing
- [ ] technique: pairwise
- [ ] technique: use-case

## SPR-FINISH-08
- acceptance.then: completion claims require gate evidence and missing evidence forces blocked or partial wording
- [ ] technique: BVA
- [ ] technique: decision-table
- [ ] technique: error-guessing
- [ ] technique: pairwise
- [ ] technique: use-case

## SPR-NOHARDPIN-05
- acceptance.then: active registries fail verification when Superpower entries hard-pin versioned cache paths
- [ ] technique: BVA
- [ ] technique: decision-table
- [ ] technique: error-guessing
- [ ] technique: pairwise
- [ ] technique: use-case

## SPR-SKILLMAP-03
- acceptance.then: each stage in the entry recap carries a named skill mapping or explicit conditional skill
- [ ] technique: BVA
- [ ] technique: decision-table
- [ ] technique: error-guessing
- [ ] technique: pairwise
- [ ] technique: use-case
