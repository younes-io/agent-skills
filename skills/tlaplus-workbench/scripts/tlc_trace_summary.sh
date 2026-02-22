#!/usr/bin/env bash
# Author: dev@younes.io
# Maintainer: dev@younes.io
set -euo pipefail

usage() {
  cat <<'EOF'
Summarize a TLC -dumpTrace json counterexample.

Usage:
  tlc_trace_summary.sh --trace path/to/counterexample.json [options]

Options:
  --trace PATH      Path to counterexample JSON (required)
  --max-steps N     Max steps to emit (default: 50)
  --format MODE     Output mode: json | text (default: json)
  -h, --help        Show this help
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 2
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
}

TRACE=""
MAX_STEPS=50
FORMAT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace)
      [[ $# -ge 2 ]] || die "missing value for --trace"
      TRACE="$2"
      shift 2
      ;;
    --max-steps)
      [[ $# -ge 2 ]] || die "missing value for --max-steps"
      MAX_STEPS="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || die "missing value for --format"
      FORMAT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$TRACE" ]] || die "--trace is required"
[[ -f "$TRACE" ]] || die "trace not found: $TRACE"
[[ "$MAX_STEPS" =~ ^[0-9]+$ ]] || die "--max-steps must be a non-negative integer"
[[ "$FORMAT" == "json" || "$FORMAT" == "text" ]] || die "--format must be one of: json, text"

require_cmd jq

summary_filter='
def parse_state_tuple:
  if (type == "array")
     and (length >= 2)
     and ((.[0] | type) == "number")
     and ((.[1] | type) == "object")
  then { "num": .[0], "state": .[1] }
  else empty
  end;

def ce:
  if (type == "object") and ((.counterexample? | type) == "object") then .counterexample
  elif type == "object" then .
  else error("counterexample json is not an object")
  end;

def parsed_states:
  (ce.state // error("counterexample.state is missing or not a list")) as $raw_states
  | if ($raw_states | type) != "array" then
      error("counterexample.state is missing or not a list")
    else
      [ $raw_states[] | parse_state_tuple ]
    end
  | if length == 0 then
      error("no parsable states found in counterexample.state")
    else
      sort_by(.num)
    end;

def parsed_edges:
  (ce.action // []) as $raw_actions
  | if ($raw_actions | type) != "array" then
      []
    else
      [
        $raw_actions[]
        | select((type == "array") and (length >= 3))
        | (.[0] | parse_state_tuple) as $from
        | (.[2] | parse_state_tuple) as $to
        | select(($from | type) == "object" and ($to | type) == "object")
        | {
            "from": $from.num,
            "to": $to.num,
            "action": (if (.[1] | type) == "object" then .[1] else { "_raw": .[1] } end)
          }
      ]
    end;

(parsed_states) as $states
| (parsed_edges) as $edges
| ($edges | map(select(.to <= .from))) as $lasso_edges
| (
    $edges
    | map(select(.to > .from))
    | reduce .[] as $e (
        {};
        if has(($e.to | tostring)) then .
        else . + { (($e.to | tostring)): { "from": $e.from, "action": $e.action } }
        end
      )
  ) as $action_by_to
| (
    reduce range(0; ($states | length)) as $i (
      { "steps": [], "prev": null };
      ($states[$i]) as $cur
      | .prev as $prev
      | (
          if $prev == null then
            ($cur.state | keys | sort)
          else
            (
              [ ($prev | keys[]?), ($cur.state | keys[]?) ]
              | unique
              | sort
              | map(select((. as $k | ($prev[$k] != $cur.state[$k]))))
            )
          end
        ) as $changed
      | .steps += [
          {
            "idx": ($i + 1),
            "state_number": $cur.num,
            "action": ($action_by_to[($cur.num | tostring)]?.action // null),
            "changed_vars": $changed
          }
        ]
      | .prev = $cur.state
    )
  ) as $acc
| {
    "states_total": ($states | length),
    "steps_emitted": ([($acc.steps | length), $max_steps] | min),
    "steps": ($acc.steps[:$max_steps]),
    "lasso_edges": $lasso_edges
  }'

summary_json="$(jq -Mce --argjson max_steps "$MAX_STEPS" "$summary_filter" "$TRACE")"

if [[ "$FORMAT" == "json" ]]; then
  printf '%s\n' "$summary_json"
  exit 0
fi

printf '%s\n' "$summary_json" | jq -r '
  (.steps[] | (
    "State \(.state_number): changed "
    + (if (.changed_vars | length) > 0 then (.changed_vars | join(", ")) else "(none)" end)
    + (if (.action | type) == "object" and (.action | has("name")) then " via \(.action.name)" else "" end)
  )),
  (if (.lasso_edges | length) > 0 then "Lasso:" else empty end),
  (.lasso_edges[]? | "  \(.from) -> \(.to)")
'
