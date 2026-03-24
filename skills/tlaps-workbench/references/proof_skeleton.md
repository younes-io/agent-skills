# TLAPS Proof Skeletons

Use these patterns as minimal starting points, then iterate.

## 1) Small Theorem Skeleton

```tla
THEOREM TypeSafety ==
  ASSUME NEW x
  PROVE  x \in S
PROOF
  <1>1. SUFFICES ASSUME x \in S PROVE x \in S OBVIOUS
  <1>2. QED BY <1>1
```

Use this when proving a direct fact and you want explicit structure.

## 2) Case-Split Skeleton

```tla
THEOREM StepPreservesInv ==
  ASSUME Inv, Next
  PROVE  Inv'
PROOF
  <1>1. CASE ActionA
    <2>1. ... 
    <2>2. QED BY <2>1 DEF ActionA
  <1>2. CASE ActionB
    <2>1. ...
    <2>2. QED BY <2>1 DEF ActionB
  <1>3. QED BY <1>1, <1>2
```

Use this when `Next` is a disjunction and each action needs a different argument.

## 3) Decomposition Pattern

```tla
THEOREM Goal ==
  ASSUME A, B
  PROVE  C
PROOF
  <1>1. SUFFICES PROVE Lemma1 /\ Lemma2
    <2>1. PROVE Lemma1
      <3>1. ...
      <3>2. QED
    <2>2. PROVE Lemma2
      <3>1. ...
      <3>2. QED
    <2>3. QED BY <2>1, <2>2
  <1>2. QED BY <1>1
```

Use this when TLAPS fails on a monolithic step.

## 4) Formula Equivalence Skeleton

```tla
THEOREM RefactorPreservesMeaning ==
  F <=> G
PROOF
  <1>1. F => G
    <2>1. ...
    <2>2. QED BY DEF F, G
  <1>2. G => F
    <2>1. ...
    <2>2. QED BY DEF F, G
  <1>3. QED BY <1>1, <1>2
```

Use this when a spec refactor needs proof of semantic preservation.

## 5) Invariant Strengthening Pattern

```tla
THEOREM InvPreserved ==
  ASSUME TypeOK, Inv, Next
  PROVE  Inv'
PROOF
  <1>1. SUFFICES PROVE Strengthening
    <2>1. ...
    <2>2. QED
  <1>2. CASE ActionA
    <2>1. ...
    <2>2. QED BY <1>1 DEF ActionA
  <1>3. CASE ActionB
    <2>1. ...
    <2>2. QED BY <1>1 DEF ActionB
  <1>4. QED BY <1>2, <1>3
```

Use this when the original invariant is too weak and one extra fact unblocks each action case.

## 6) Definition Expansion Guidance

- Expand only required definitions with `BY DEF Foo, Bar`.
- Avoid broad expansion unless debugging.
- Prefer proving helper lemmas over repeated broad `DEF` lists.

## 7) Practical Ordering

1. State theorem with exact assumptions.
2. Pick the proof class before choosing a skeleton.
3. Add one decomposition step (`SUFFICES` or `CASE`).
4. Prove subgoals with short steps.
5. Close with explicit `QED BY ...`.
