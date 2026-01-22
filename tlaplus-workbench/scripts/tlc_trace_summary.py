#!/usr/bin/env python3
"""
Summarize a TLC -dumpTrace json counterexample into a small, agent-friendly form.

This is intentionally dependency-free (stdlib only) and tolerant of minor schema
changes by treating unknown fields as opaque.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.dont_write_bytecode = True


@dataclass(frozen=True)
class TraceStep:
    idx: int
    state_number: int
    action: Optional[Dict[str, Any]]
    changed_vars: List[str]


def _stable_json(v: Any) -> str:
    # Used for deep-ish equality that is stable across dict key ordering.
    try:
        return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    except TypeError:
        return repr(v)


def _deep_equal(a: Any, b: Any) -> bool:
    if type(a) is not type(b):
        return False
    if isinstance(a, (dict, list, str, int, float, bool)) or a is None:
        return a == b
    return _stable_json(a) == _stable_json(b)


def _parse_state_tuple(item: Any) -> Optional[Tuple[int, Dict[str, Any]]]:
    # Expected format from tlc2.value.impl.CounterExample serialization:
    #   [ stateNumber, { var: value, ... } ]
    if isinstance(item, list) and len(item) >= 2 and isinstance(item[0], int) and isinstance(item[1], dict):
        return item[0], item[1]
    return None


def _extract_counterexample(doc: Any) -> Dict[str, Any]:
    if isinstance(doc, dict) and "counterexample" in doc and isinstance(doc["counterexample"], dict):
        return doc["counterexample"]
    if isinstance(doc, dict):
        # Be tolerant if the file is the CounterExample record itself.
        return doc
    raise ValueError("counterexample json is not an object")


def summarize_counterexample_json(doc: Any, *, max_steps: Optional[int] = None) -> Dict[str, Any]:
    ce = _extract_counterexample(doc)

    raw_states = ce.get("state")
    if not isinstance(raw_states, list):
        raise ValueError("counterexample.state is missing or not a list")

    parsed_states: List[Tuple[int, Dict[str, Any]]] = []
    for it in raw_states:
        st = _parse_state_tuple(it)
        if st is None:
            continue
        parsed_states.append(st)

    if not parsed_states:
        raise ValueError("no parsable states found in counterexample.state")

    parsed_states.sort(key=lambda t: t[0])

    raw_actions = ce.get("action")
    action_by_to: Dict[int, Dict[str, Any]] = {}
    lasso_edges: List[Dict[str, Any]] = []
    if isinstance(raw_actions, list):
        for edge in raw_actions:
            # Edge format: [ fromStateTuple, actionRecord, toStateTuple ]
            if not (isinstance(edge, list) and len(edge) >= 3):
                continue
            from_st = _parse_state_tuple(edge[0])
            action = edge[1] if isinstance(edge[1], dict) else None
            to_st = _parse_state_tuple(edge[2])
            if from_st is None or to_st is None:
                continue
            from_n, _ = from_st
            to_n, _ = to_st
            if action is None:
                action = {"_raw": edge[1]}

            # Detect lasso-closing edge (to an earlier state).
            if to_n <= from_n:
                lasso_edges.append({"from": from_n, "to": to_n, "action": action})
                continue

            # Regular step edge. Prefer first mapping if duplicates show up.
            action_by_to.setdefault(to_n, {"from": from_n, "action": action})

    steps: List[TraceStep] = []
    prev_state: Optional[Dict[str, Any]] = None
    for i, (state_num, state) in enumerate(parsed_states, start=1):
        changed: List[str] = []
        if prev_state is None:
            changed = sorted(state.keys())
        else:
            keys = set(prev_state.keys()) | set(state.keys())
            for k in keys:
                if not _deep_equal(prev_state.get(k), state.get(k)):
                    changed.append(k)
            changed.sort()

        action_rec: Optional[Dict[str, Any]] = None
        if state_num in action_by_to:
            action_rec = action_by_to[state_num]["action"]

        steps.append(
            TraceStep(
                idx=i,
                state_number=state_num,
                action=action_rec,
                changed_vars=changed,
            )
        )
        prev_state = state

        if max_steps is not None and len(steps) >= max_steps:
            break

    return {
        "states_total": len(parsed_states),
        "steps_emitted": len(steps),
        "steps": [
            {
                "idx": s.idx,
                "state_number": s.state_number,
                "action": s.action,
                "changed_vars": s.changed_vars,
            }
            for s in steps
        ],
        "lasso_edges": lasso_edges,
    }


def _cmd() -> int:
    ap = argparse.ArgumentParser(description="Summarize a TLC -dumpTrace json counterexample.")
    ap.add_argument("--trace", required=True, help="Path to counterexample.json produced by TLC -dumpTrace json")
    ap.add_argument("--max-steps", type=int, default=50, help="Max steps to emit (default: 50)")
    ap.add_argument("--format", choices=["json", "text"], default="json")
    args = ap.parse_args()

    path = Path(args.trace)
    doc = json.loads(path.read_text(encoding="utf-8"))
    summary = summarize_counterexample_json(doc, max_steps=args.max_steps)

    if args.format == "json":
        sys.stdout.write(json.dumps(summary, indent=2, ensure_ascii=True) + "\n")
        return 0

    # Minimal text mode for quick scanning.
    for s in summary["steps"]:
        line = f"State {s['state_number']}: changed {', '.join(s['changed_vars']) if s['changed_vars'] else '(none)'}"
        if s.get("action") and isinstance(s["action"], dict) and "name" in s["action"]:
            line = f"{line} via {s['action']['name']}"
        sys.stdout.write(line + "\n")
    if summary["lasso_edges"]:
        sys.stdout.write("Lasso:\n")
        for e in summary["lasso_edges"]:
            sys.stdout.write(f"  {e['from']} -> {e['to']}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(_cmd())
