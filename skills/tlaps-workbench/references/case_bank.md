# TLAPS Case Bank

Discussion-derived proof classes and example families to use as calibration targets.

## Formula Equivalence for Refactors

- Use case: prove `F <=> G` after rewriting a complex formula during spec cleanup.
- Why it matters: this gives unbounded proof evidence for refactors where TLC would only provide bounded confidence.
- Starter shape:

```tla
THEOREM F <=> G
PROOF
  <1>1. F => G
    ...
  <1>2. G => F
    ...
  <1>3. QED BY <1>1, <1>2
```

## Inductive Invariant Discovery and Strengthening

- Common hard part: the theorem goal is fine, but the current invariant is too weak to make the inductive step go through.
- Skill behavior: propose the smallest strengthening invariant or helper lemma explicitly instead of pretending the original context is enough.

## Suggested Non-Trivial Example Families

- `EWD840`: classic proof-heavy example with structured invariant reasoning.
- `EWD998`: includes fold-related facts; imported theorems such as `FoldsTheorems` from CommunityModules may be reusable instead of reproving everything locally.
- `LamportMutex`: distributed-state safety proof with non-trivial decomposition.
- `Paxos`: rich protocol proof where decomposition and invariant management matter.
- `BlockingQueueSplit` and `BlockingQueueFair`: refinement-oriented proofs that exercise abstraction relations.
- `BlockingQueuePoisonPill` and `BlockingQueuePoisonApple`: missing safety/liveness proofs that can serve as open-ended targets.
- starvation freedom for the blocking queue family: liveness stretch goal with fairness/variant obligations.

## How to Use This Bank

1. Pick the closest proof class before editing any theorem.
2. Check for imported modules or existing theorems that should be cited explicitly.
3. Prefer a narrowly scoped helper lemma or strengthening invariant over broad proof search.
4. State clearly whether the task is safety, liveness, refinement, or formula equivalence.
