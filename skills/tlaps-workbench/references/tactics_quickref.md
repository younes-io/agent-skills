# TLAPS Tactics and Backend Quick Reference

Use this guide after structural proof cleanup.

## Escalation Order

1. Keep default TLAPS behavior and fix proof structure first.
2. Add explicit intermediate lemmas/facts.
3. Expand targeted definitions (`BY DEF ...`).
4. Change backend strategy for specific stubborn obligations.

## What to Prefer

- Prefer local proof decomposition over global backend tuning.
- Prefer explicit fact flow (`HAVE`, `SUFFICES`, labeled steps) over large `BY` lists.
- Prefer narrow definition expansion over broad expansion.

## When to Consider Backend Changes

- Arithmetic-heavy subgoal persists after decomposition.
- Set/function extensionality style obligations remain isolated.
- One obligation class fails repeatedly while others are stable.

## Minimal Operational Guidance

- Run the checker script first:

```bash
scripts/tlaps_check.sh --spec path/to/Foo.tla
```

- If backend customization is required in your environment:
- use a `tlapm` wrapper script
- pass wrapper path via `--tlapm /path/to/wrapper`

This keeps the skill workflow stable while allowing local backend policy.

## Documentation Hygiene

- Record why a backend/tactic change was needed.
- Keep such changes localized to the failing theorem or obligation class.
- Revert broad tactic changes once the failing obligations are isolated.
