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

\* Safety baseline.
Spec == Init /\ [][Next]_Vars

\* Optional liveness fairness (only when checking liveness properties).
SomeAcquire == \E n \in Nodes: Acquire(n)
FairSpec == Spec /\ WF_Vars(SomeAcquire)

\* Example safety property (invariant)
MutualExclusion == owner # NULL => owner \in Nodes

====
```

Notes:
- Prefer `TypeOK` as an invariant in the `.cfg` rather than baking types into `Next`.
- Model uncertainty explicitly (nondeterministic actions, bounded message sets, bounded buffers).
- Keep `Next` permissive; use `CONSTRAINT` only when you understand the coverage tradeoff.
- Keep the variable tuple name canonical (`Vars`) and use that exact casing everywhere (`[][Next]_Vars`, `WF_Vars(...)`, `SF_Vars(...)`).

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

Deadlock guidance:
- Keep `CHECK_DEADLOCK TRUE` by default.
- If the model has intentional terminal states, define them explicitly and report whether deadlock is expected terminal completion or an unexpected stall.

## Common fast iteration moves

- TLC fails with counterexample:
  - First: explain the trace (state deltas, action, violated property).
  - Then: decide whether the design is wrong or the model is missing an assumption.
  - Patch minimally, rerun.

- TLC passes:
  - Verify non-vacuity before calling it a pass:
    - At least one non-stuttering transition is reachable.
    - Any `CONSTRAINT` / `ACTION_CONSTRAINT` is documented with its coverage tradeoff.
    - Checked properties are not tautological/trivially weakened.
  - If vacuity checks are inconclusive, report "inconclusive coverage" instead of pass.
  - Increase bounds slightly (nodes/messages/time).
  - Add the next property.
  - Call out what is still unmodeled.
