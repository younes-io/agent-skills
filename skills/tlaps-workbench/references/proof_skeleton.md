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

## 4) Definition Expansion Guidance

- Expand only required definitions with `BY DEF Foo, Bar`.
- Avoid broad expansion unless debugging.
- Prefer proving helper lemmas over repeated broad `DEF` lists.

## 5) Practical Ordering

1. State theorem with exact assumptions.
2. Add one decomposition step (`SUFFICES` or `CASE`).
3. Prove subgoals with short steps.
4. Close with explicit `QED BY ...`.
