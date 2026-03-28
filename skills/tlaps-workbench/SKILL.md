---
name: tlaps-workbench
description: "Write and iteratively refine TLA+ theorem proofs in `.tla` modules with TLAPS (`tlapm`); run proof checks and summarize proved vs failed/omitted obligations with explicit assumptions and trust boundaries. Use when asked to create/fix `THEOREM` or `PROOF` blocks, diagnose TLAPS failures, tune proof decomposition/tactics/backends, or report theorem-proving progress."
---

# TLAPS Workbench

## Outputs

- Updated proof-bearing TLA+ module(s): `*.tla`
- TLAPS run artifacts: `.tlaps-workbench/runs/<run-id>/...`

## Non-Negotiables (Honesty Rules)

- Never claim full system correctness from a partial proof.
- Always report what was proved, what failed, and what was omitted.
- Always surface trust boundaries (`ASSUME`, `AXIOM`, omitted proofs, imported facts).
- Never conflate TLC outcomes with TLAPS outcomes; treat them as different evidence.
- Always keep theorem statements stable while debugging unless the user approves spec changes.

## Workflow (Theorem -> Proof -> TLAPS -> Iterate)

### 1) Pin Down Target and Trust Boundary

Record:
- theorem statement(s) in scope
- assumptions/environment model
- required imported definitions/lemmas
- proof granularity target (quick progress vs fully structured proof)

If theorem intent is ambiguous, state candidate interpretations and choose one explicitly.

### 2) Draft Minimal Hierarchical Proof Structure

Start with the smallest stable structure:
- `THEOREM ...`
- `PROOF`
- `SUFFICES`, `HAVE`, `CASE`, `PICK`, `QED` as needed

Prefer explicit sub-lemmas over long single-step `BY` clauses.
Use `BY DEF ...` only for required definitions.
Formula-equivalence proofs for refactors are a supported pattern, for example `THEOREM F <=> G BY DEF F, G`.

### 3) Run TLAPS Deterministically

Prereqs:
- `bash`
- `jq`
- `tlapm`

Run from the skill directory:

```bash
scripts/tlaps_check.sh --spec path/to/Foo.tla
```

Artifacts:
- `.tlaps-workbench/runs/<run-id>/summary.json`
- `.tlaps-workbench/runs/<run-id>/tlaps.stdout`
- `.tlaps-workbench/runs/<run-id>/tlaps.stderr`

### 4) Triage Failing Obligations

Classify failures before editing:
- missing context facts
- insufficient decomposition
- missing definition expansion
- backend/tactic mismatch
- malformed theorem/proof structure

Patch minimally, then re-run.

### 5) Report Progress Precisely

Report:
- theorem(s) checked
- proved/failed/omitted obligations
- assumptions and trust boundaries
- remaining proof gaps

If counts are inconclusive, say so explicitly.
Common refactor-proof target: prove a rewritten formula or action is equivalent to the original, rather than only model-checking `F <=> G` with TLC.

## Resources

### scripts/

- `scripts/tlaps_check.sh`: run `tlapm`, capture logs, emit `summary.json`

### references/

- `references/proof_skeleton.md`: minimal hierarchical proof templates
- `references/proof_debugging.md`: failure taxonomy and remediation playbook
- `references/tactics_quickref.md`: tactic/backend guidance and escalation order
