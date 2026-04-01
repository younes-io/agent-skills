# TLAPS Local Moves

Use these moves almost mechanically. They are the first pass for shaping a
proof before you reach for stronger tactics or backend changes.

## Goal-Side Moves

- Goal `P /\ Q`: split into separate subgoals and prove each conjunct.
- Goal `P \/ Q`: close the disjunction by proving one disjunct explicitly; in
  some branches, assumptions that rule out the other disjunct may guide which
  side to prove.
- Goal `P => Q`: switch to `ASSUME P PROVE Q`, often via `SUFFICES`.
- Goal `\A x : P(x)` or `\A x \in S : P(x)`: `TAKE` an arbitrary witness and
  prove the body.
- Goal `\E x : P(x)` or `\E x \in S : P(x)`: provide a `WITNESS`, then prove
  the instantiated body.
- Goal `F <=> G`: split into `F => G` and `G => F`.

## Assumption-Side Moves

- Assumption `P /\ Q`: use the conjuncts separately.
- Assumption `P \/ Q`: split the proof with `CASE P` and `CASE Q`.
- Assumption `\E x : P(x)` or `\E x \in S : P(x)`: `PICK` a fresh witness and
  continue with the instantiated fact.
- Assumption `P => Q`: derive `Q` only after establishing `P`; do not treat the
  implication as free context.

## First Choice By Outer Shape

- If the goal is an implication, assume the antecedent first.
- If the goal is universal, `TAKE` an arbitrary element first.
- If the goal is existential, search for a concrete witness first.
- If the goal is an equivalence, split directions first.
- If `Next` is a disjunction of actions, `CASE` on the action first.
- If an action proof keeps failing, suspect a missing strengthening fact before
  changing backends.

## High-Value TLAPS Patterns

- Direct fact: expand the needed definitions and push assumptions toward the
  goal with short `HAVE` steps.
- Case split: when branches need different arguments, isolate them with `CASE`
  rather than one large `BY`.
- Witness proof: for existential goals, choose the witness early and prove the
  instantiated obligation explicitly.
- Invariant preservation: split base case vs step case, then split `Next` by
  action.
- Definition reduction: if the statement is still too compressed to move, expand
  only the definitions that matter.

## Guardrails

- Prefer local proof reshaping over long opaque `BY` clauses.
- Do not jump to backend tuning before trying the matching logical move.
- Do not introduce a witness unless you can prove it satisfies the target fact.
- Do not `PICK` from an existential assumption without keeping the instantiated
  fact in scope.
- If the structure is still unclear after one decomposition step, ask whether
  the theorem needs a helper lemma or strengthening invariant.
