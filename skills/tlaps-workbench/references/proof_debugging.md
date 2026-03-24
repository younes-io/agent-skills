# TLAPS Proof Debugging Playbook

Use this checklist when `tlapm` reports proof failures.

## 1) Identify Failure Class

- Induction gap: the current invariant/helper facts are too weak for the step being proved.
- Context gap: required fact not available where the step is proved.
- Structure gap: proof step is too large or mixes unrelated goals.
- Definition gap: theorem depends on hidden definitions not expanded.
- Assumption gap: theorem statement is too strong for current assumptions.
- Backend mismatch: default backend cannot discharge a specific arithmetic/set obligation.
- Goal mismatch: the real task is better phrased as refinement/equivalence/auxiliary lemma work than as the current top-level step.

## 2) Apply Fixes in This Order

1. Shrink the failing step into smaller subgoals (`SUFFICES`, `HAVE`, `CASE`).
2. Make required facts explicit in scope (`USE`, prior step references, helper lemmas).
3. Add the smallest strengthening invariant or helper lemma that makes the obligation inductive.
4. Expand only necessary definitions (`BY DEF ...`).
5. Rewrite the local argument to remove ambiguity.
6. Change backend/tactic only for the remaining hard obligation.

## 3) Common Failure Patterns

### "Obvious" step fails

- Replace `OBVIOUS` with explicit references (`BY <n>m, DEF Foo`).
- Add intermediate facts with `HAVE`.

### Case proof fails for one branch

- Isolate the failing branch as a dedicated sub-lemma.
- Check that branch assumptions are actually introduced.

### Inductive step keeps failing after decomposition

- Stop broadening `BY` lists and ask what fact is missing from the invariant.
- Introduce one strengthening lemma, then rerun before adding more.

### Refactor proof stalls on `F <=> G`

- Split the equivalence into two directions.
- Expand only the definitions that differ materially between `F` and `G`.

### Repeated failures across many steps

- Check theorem statement for missing assumptions.
- Factor reusable facts into named lemmas.
- Check imported modules for an existing theorem you should cite instead of reproving.

## 4) Reporting Template

Report each run as:

1. Theorem(s) attempted.
2. Obligation status (proved/failed/omitted if available).
3. Exact edits made since previous run.
4. Remaining blockers and next targeted edit.

## 5) Guardrails

- Do not weaken theorem statements silently.
- Do not present new strengthening invariants as already established facts; prove them or mark them as new obligations.
- Do not hide unproved steps; mark omissions explicitly.
- Do not switch backends/tactics repeatedly without structural diagnosis first.
