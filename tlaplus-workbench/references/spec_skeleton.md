# Minimal TLA+ + TLC Skeleton (Copy/Patch, Then Iterate)

Goal: get to the smallest executable model quickly, then tighten properties/bounds.

## Spec skeleton

```tla
---- MODULE Foo ----
EXTENDS Naturals, Sequences, TLC

\* Keep the model finite by making these small in the .cfg.
CONSTANTS Nodes, Values

VARIABLES x, owner

Vars == <<x, owner>>

TypeOK ==
  /\ x \in Values
  /\ owner \in Nodes \cup {NULL}

Init ==
  /\ x \in Values
  /\ owner = NULL

\* Actions: always say what changes and explicitly UNCHANGED the rest.
Acquire(n) ==
  /\ n \in Nodes
  /\ owner = NULL
  /\ owner' = n
  /\ UNCHANGED x

Release(n) ==
  /\ n \in Nodes
  /\ owner = n
  /\ owner' = NULL
  /\ UNCHANGED x

Next ==
  \E n \in Nodes: Acquire(n) \/ Release(n)

\* Only needed if you check temporal properties.
Spec == Init /\ [][Next]_Vars

\* Example safety property (invariant)
MutualExclusion == owner # NULL => owner \in Nodes

====
```

Notes:
- Prefer `TypeOK` as an invariant in the `.cfg` rather than baking types into `Next`.
- Model uncertainty explicitly (nondeterministic actions, bounded message sets, bounded buffers).
- Keep `Next` permissive; use `CONSTRAINT` only when you understand the coverage tradeoff.

## TLC `.cfg` skeleton

```tla
SPECIFICATION Spec

CONSTANTS
  Nodes = {n1, n2, n3}
  Values = {v1, v2}

INVARIANT
  TypeOK
  MutualExclusion

CHECK_DEADLOCK TRUE
```

## Common fast iteration moves

- TLC fails with counterexample:
  - First: explain the trace (state deltas, action, violated property).
  - Then: decide whether the design is wrong or the model is missing an assumption.
  - Patch minimally, rerun.

- TLC passes:
  - Increase bounds slightly (nodes/messages/time).
  - Add the next property.
  - Call out what is still unmodeled.

