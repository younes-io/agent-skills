---
name: tla-proof
description: "Write and iteratively refine TLA+ theorem proofs in `.tla` modules with TLAPS (`tlapm`); run proof checks and summarize proved vs failed/omitted obligations with explicit assumptions and trust boundaries. Use when asked to create or fix `THEOREM` or `PROOF` blocks, diagnose TLAPS failures, strengthen inductive invariants, prove equivalence, or tune proof structure."
---

# TLA+ Proof

## Outputs

- Updated proof-bearing TLA+ module(s): `*.tla`
- TLAPS run artifacts: `.tla-proof/runs/<run-id>/...`

## Non-Negotiables (Honesty Rules)

- Never claim full system correctness from a partial proof.
- Always report what was proved, what failed, and what was omitted.
- Always surface trust boundaries (`ASSUME`, `AXIOM`, omitted proofs, imported facts).
- Never conflate TLC outcomes with TLAPS outcomes; treat them as different evidence.
- Always keep theorem statements stable while debugging unless the user approves spec changes.

## Workflow (Target Class -> Proof Plan -> TLAPS -> Iterate)

### 1) Pin Down Target and Trust Boundary

Record:
- theorem statement(s) in scope
- proof class: direct fact, inductive invariant, refinement, formula equivalence, safety, liveness
- assumptions/environment model
- required imported definitions/lemmas
- candidate strengthening invariants or helper lemmas if the target does not look inductive yet
- proof granularity target (quick progress vs fully structured proof)

If theorem intent is ambiguous, state candidate interpretations and choose one explicitly.
If the user is refactoring a spec and wants semantic preservation, consider a direct equivalence theorem (`F <=> G`) instead of only bounded TLC evidence.

### 2) Draft Minimal Hierarchical Proof Structure

Start with the smallest stable structure:
- `THEOREM ...`
- `PROOF`
- `SUFFICES`, `HAVE`, `CASE`, `PICK`, `TAKE`, `WITNESS`, `QED` as needed

Prefer explicit sub-lemmas over long single-step `BY` clauses.
Use `BY DEF ...` only for required definitions.
Formula-equivalence proofs for refactors are a supported pattern, for example `THEOREM F <=> G BY DEF F, G`.
Match the structure to the proof class:
- inductive invariant/safety: isolate base case vs step case and split `Next` by action
- refinement: state the abstraction relation/refinement mapping and prove init/step obligations separately
- formula equivalence: start with `THEOREM F <=> G`; if a one-line proof fails, split into `F => G` and `G => F`
- liveness/starvation freedom: pin down fairness and ranking assumptions before proof search, then expect auxiliary lemmas

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
- `.tla-proof/runs/<run-id>/summary.json`
- `.tla-proof/runs/<run-id>/tlaps.stdout`
- `.tla-proof/runs/<run-id>/tlaps.stderr`

### 4) Triage Failing Obligations

Classify failures before editing:
- missing strengthening invariant or helper lemma
- missing context facts
- insufficient decomposition
- missing definition expansion
- backend/tactic mismatch
- malformed theorem/proof structure
- wrong target framing (for example, an equivalence theorem is the real goal)

Patch minimally, then re-run.
If the same inductive step keeps failing, stop cycling tactics and propose the smallest strengthening fact that would make the step go through.

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
- `references/local_moves.md`: TLAPS-specific logical moves and proof-shape defaults
- `references/proof_debugging.md`: failure taxonomy and remediation playbook
- `references/tactics_quickref.md`: tactic/backend guidance and escalation order
- `references/case_bank.md`: discussion-derived proof classes and non-trivial example ideas
