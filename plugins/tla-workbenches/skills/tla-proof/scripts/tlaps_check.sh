#!/usr/bin/env bash
# Author: dev@younes.io
# Maintainer: dev@younes.io
set -euo pipefail

usage() {
  cat <<'EOF'
Run TLAPS (tlapm) and emit a machine-readable run summary JSON.

Usage:
  tlaps_check.sh --spec path/to/Foo.tla [options]

Options:
  --spec PATH          Path to root .tla module (required)
  --tlapm BIN          tlapm executable or absolute path (default: tlapm)
  --timeout-secs N     Kill tlapm after N seconds (default: 0 = no timeout)
  --out-root PATH      Run artifact root (default: <spec-dir>/.tla-proof/runs)
  --max-lines N        Max stdout/stderr lines to keep in summary excerpts (default: 200)
  -h, --help           Show this help
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

expand_user_path() {
  local p="$1"
  case "$p" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s\n' "$HOME" "${p#~/}"
      ;;
    *)
      printf '%s\n' "$p"
      ;;
  esac
}

abs_path() {
  local p="$1"
  local d
  local b
  if [[ -d "$p" ]]; then
    (cd "$p" && pwd -P)
    return
  fi
  d="$(dirname "$p")"
  b="$(basename "$p")"
  (cd "$d" && printf '%s/%s\n' "$(pwd -P)" "$b")
}

abs_existing_file() {
  local p
  p="$(expand_user_path "$1")"
  [[ -f "$p" ]] || return 1
  abs_path "$p"
}

abs_maybe_missing() {
  local p
  p="$(expand_user_path "$1")"
  if [[ "$p" == /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s/%s\n' "$(pwd -P)" "$p"
  fi
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | awk '{print $NF}'
    return
  fi
  return 1
}

mk_run_id() {
  local spec_path="$1"
  local ts
  local spec_h
  ts="$(date '+%Y%m%d-%H%M%S')"
  spec_h="$(sha256_file "$spec_path" 2>/dev/null | cut -c1-8 || true)"
  if [[ -n "$spec_h" ]]; then
    printf '%s-%s\n' "$ts" "$spec_h"
  else
    printf '%s\n' "$ts"
  fi
}

iso_utc_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

quote_cmd() {
  local out=""
  local part
  local q
  for part in "$@"; do
    printf -v q '%q' "$part"
    if [[ -n "$out" ]]; then
      out="$out $q"
    else
      out="$q"
    fi
  done
  printf '%s\n' "$out"
}

json_num_or_null() {
  local v="${1:-}"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$v"
  else
    printf 'null\n'
  fi
}

collect_descendants() {
  local root_pid="$1"
  local frontier
  local descendants
  local next_frontier
  local pid
  local children

  frontier="$root_pid"
  descendants=""
  while [[ -n "$frontier" ]]; do
    next_frontier=""
    for pid in $frontier; do
      children="$(
        ps -eo pid=,ppid= 2>/dev/null | awk -v p="$pid" '$2 == p { print $1 }'
      )"
      if [[ -n "$children" ]]; then
        descendants="${descendants}${descendants:+$'\n'}${children}"
        next_frontier="${next_frontier}${next_frontier:+ }${children//$'\n'/ }"
      fi
    done
    frontier="$next_frontier"
  done

  if [[ -n "$descendants" ]]; then
    printf '%s\n' "$descendants" | awk '!seen[$0]++'
  fi
}

terminate_process_tree() {
  local root_pid="$1"
  local pids
  local descendants

  descendants="$(collect_descendants "$root_pid" || true)"
  pids=""
  if [[ -n "$descendants" ]]; then
    pids="${descendants//$'\n'/ }"
  fi
  pids="${pids}${pids:+ }${root_pid}"
  if [[ -n "$pids" ]]; then
    kill $pids 2>/dev/null || true
  fi

  sleep 2

  descendants="$(collect_descendants "$root_pid" || true)"
  pids=""
  if [[ -n "$descendants" ]]; then
    pids="${descendants//$'\n'/ }"
  fi
  if kill -0 "$root_pid" 2>/dev/null; then
    pids="${pids}${pids:+ }${root_pid}"
  fi
  if [[ -n "$pids" ]]; then
    kill -9 $pids 2>/dev/null || true
  fi
}

extract_after_keyword() {
  local line="$1"
  local keywords="$2"
  local match
  match="$(printf '%s\n' "$line" | grep -Eo "(${keywords})[^0-9]*[0-9]+" 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$match" ]]; then
    printf '%s\n' "$match" | sed -nE 's/.*[^0-9]([0-9]+)$/\1/p'
  fi
}

extract_before_keyword() {
  local line="$1"
  local keywords="$2"
  local match
  match="$(printf '%s\n' "$line" | grep -Eo "[0-9]+[^[:alnum:]]*(${keywords})" 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$match" ]]; then
    printf '%s\n' "$match" | sed -nE 's/^([0-9]+).*/\1/p'
  fi
}

extract_count_for_keywords() {
  local line="$1"
  local keywords="$2"
  local value

  value="$(extract_after_keyword "$line" "$keywords")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return
  fi
  value="$(extract_before_keyword "$line" "$keywords")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  fi
}

parse_real_tlapm_summary_line() {
  local line="$1"

  if [[ "$line" =~ all[[:space:]]+([0-9]+)[[:space:]]+obligations?[[:space:]]+proved\.?$ ]]; then
    COUNT_TOTAL="${BASH_REMATCH[1]}"
    COUNT_PROVED="${BASH_REMATCH[1]}"
    COUNT_FAILED="0"
    COUNT_OMITTED="0"
    COUNT_UNKNOWN="0"
    return 0
  fi

  if [[ "$line" =~ ([0-9]+)[[:space:]]*/[[:space:]]*([0-9]+)[[:space:]]+obligations?[[:space:]]+failed\.?$ ]]; then
    local failed_count="${BASH_REMATCH[1]}"
    local total_count="${BASH_REMATCH[2]}"
    local proved_count=0

    if (( failed_count > total_count )); then
      append_note "Parsed failed obligations exceeded parsed total obligations; leaving counts as null."
      COUNT_TOTAL=""
      COUNT_PROVED=""
      COUNT_FAILED=""
      COUNT_OMITTED=""
      COUNT_UNKNOWN=""
      return 0
    fi

    proved_count=$((total_count - failed_count))
    COUNT_TOTAL="$total_count"
    COUNT_PROVED="$proved_count"
    COUNT_FAILED="$failed_count"
    COUNT_OMITTED="0"
    COUNT_UNKNOWN="0"
    return 0
  fi

  return 1
}

build_excerpt_json() {
  local path="$1"
  local max_lines="$2"
  if [[ ! -f "$path" ]]; then
    printf '[]\n'
    return
  fi
  head -n "$max_lines" "$path" | jq -R . | jq -s .
}

build_notes_json() {
  if (( ${#NOTES[@]} == 0 )); then
    printf '[]\n'
    return
  fi
  printf '%s\n' "${NOTES[@]}" | jq -R . | jq -s .
}

append_note() {
  NOTES+=("$1")
}

parse_counts() {
  local combined="$1"
  local line
  local lower_line
  local line_no=0
  local total
  local proved
  local failed
  local omitted
  local field_count
  local progress_hint
  local score
  local best_score=-1
  local best_line_no=0
  local best_total=""
  local best_proved=""
  local best_failed=""
  local best_omitted=""
  local best_progress_hint=0
  local best_field_count=0
  COUNT_TOTAL=""
  COUNT_PROVED=""
  COUNT_FAILED=""
  COUNT_OMITTED=""
  COUNT_UNKNOWN=""

  if [[ ! -s "$combined" ]]; then
    append_note "No TLAPS output was available for obligation parsing."
    return
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    lower_line="$(printf '%s\n' "$line" | tr '[:upper:]' '[:lower:]')"

    if parse_real_tlapm_summary_line "$lower_line"; then
      return
    fi

    total="$(extract_count_for_keywords "$lower_line" 'total|obligations?')"
    proved="$(extract_count_for_keywords "$lower_line" 'proved|discharged|checked')"
    failed="$(extract_count_for_keywords "$lower_line" 'failed|unproved|not[[:space:]]+proved|remaining')"
    omitted="$(extract_count_for_keywords "$lower_line" 'omitted|skipped|unchecked')"

    # TLAPM commonly emits final success summaries such as:
    #   [INFO]: All 1 obligation proved.
    # Treat this as a trustworthy terminal summary with zero failed/omitted obligations.
    if [[ "$lower_line" =~ all[[:space:]]+([0-9]+)[[:space:]]+obligations?[[:space:]]+proved ]]; then
      total="${BASH_REMATCH[1]}"
      proved="${BASH_REMATCH[1]}"
      failed="0"
      omitted="0"
    fi

    # TLAPM also emits failure summaries such as:
    #   [ERROR]: 1/1 obligation failed.
    # Treat this as a terminal summary with all obligations accounted for.
    if [[ "$lower_line" =~ ([0-9]+)[[:space:]]*/[[:space:]]*([0-9]+)[[:space:]]+obligations?[[:space:]]+failed ]]; then
      failed="${BASH_REMATCH[1]}"
      total="${BASH_REMATCH[2]}"
      if [[ "$total" =~ ^[0-9]+$ && "$failed" =~ ^[0-9]+$ && "$failed" -le "$total" ]]; then
        proved="$((total - failed))"
        omitted="0"
      fi
    fi

    field_count=0
    [[ -n "$total" ]] && field_count=$((field_count + 1))
    [[ -n "$proved" ]] && field_count=$((field_count + 1))
    [[ -n "$failed" ]] && field_count=$((field_count + 1))
    [[ -n "$omitted" ]] && field_count=$((field_count + 1))

    if [[ -z "$total" || "$field_count" -lt 2 ]]; then
      continue
    fi

    progress_hint=0
    if [[ "$lower_line" =~ [0-9]+[[:space:]]*(/|of)[[:space:]]*[0-9]+ && -z "$failed" && -z "$omitted" ]]; then
      progress_hint=1
    fi

    score=$((field_count * 100))
    if (( progress_hint == 0 )); then
      score=$((score + 25))
    fi

    if (( score > best_score || (score == best_score && line_no > best_line_no) )); then
      best_score="$score"
      best_line_no="$line_no"
      best_total="$total"
      best_proved="$proved"
      best_failed="$failed"
      best_omitted="$omitted"
      best_progress_hint="$progress_hint"
      best_field_count="$field_count"
    fi
  done <"$combined"

  if (( best_score < 0 )); then
    append_note "Could not parse trustworthy obligation summary counts from TLAPS output."
    return
  fi

  COUNT_TOTAL="$best_total"
  COUNT_PROVED="$best_proved"
  COUNT_FAILED="$best_failed"
  COUNT_OMITTED="$best_omitted"

  if [[ "$best_progress_hint" == "1" && -z "$COUNT_FAILED" && -z "$COUNT_OMITTED" ]]; then
    if [[ "$COUNT_TOTAL" =~ ^[0-9]+$ && "$COUNT_PROVED" =~ ^[0-9]+$ && "$COUNT_PROVED" -lt "$COUNT_TOTAL" ]]; then
      COUNT_TOTAL=""
      COUNT_PROVED=""
      COUNT_FAILED=""
      COUNT_OMITTED=""
      append_note "Detected progress-style obligation counts without final summary; leaving counts as null."
      return
    fi
  fi

  if [[ "$COUNT_TOTAL" =~ ^[0-9]+$ && "$COUNT_PROVED" =~ ^[0-9]+$ && "$COUNT_FAILED" =~ ^[0-9]+$ && "$COUNT_OMITTED" =~ ^[0-9]+$ ]]; then
    local subtotal
    subtotal=$((COUNT_PROVED + COUNT_FAILED + COUNT_OMITTED))
    if (( COUNT_TOTAL >= subtotal )); then
      COUNT_UNKNOWN=$((COUNT_TOTAL - subtotal))
    else
      COUNT_UNKNOWN=0
      append_note "Parsed counts exceeded parsed total obligations; set unknown=0."
    fi
  else
    COUNT_UNKNOWN=""
    if [[ "$best_field_count" -lt 4 ]]; then
      append_note "Parsed partial obligation summary counts; unknown set to null."
    fi
  fi
}

write_summary() {
  local status="$1"
  local exit_code="$2"
  local timed_out_json="$3"
  local combined="$run_dir/tlaps.combined"
  local notes_json
  local stdout_excerpt_json
  local stderr_excerpt_json
  local total_json
  local proved_json
  local failed_json
  local omitted_json
  local unknown_json

  : >"$combined"
  if [[ -f "$stdout_path" ]]; then
    cat "$stdout_path" >>"$combined" || true
  fi
  if [[ -f "$stderr_path" ]]; then
    cat "$stderr_path" >>"$combined" || true
  fi

  NOTES=()
  if (( MAX_LINES == 0 )); then
    append_note "--max-lines is 0; excerpts are empty by configuration."
  fi
  parse_counts "$combined"

  stdout_excerpt_json="$(build_excerpt_json "$stdout_path" "$MAX_LINES")"
  stderr_excerpt_json="$(build_excerpt_json "$stderr_path" "$MAX_LINES")"
  notes_json="$(build_notes_json)"

  total_json="$(json_num_or_null "$COUNT_TOTAL")"
  proved_json="$(json_num_or_null "$COUNT_PROVED")"
  failed_json="$(json_num_or_null "$COUNT_FAILED")"
  omitted_json="$(json_num_or_null "$COUNT_OMITTED")"
  unknown_json="$(json_num_or_null "$COUNT_UNKNOWN")"

  jq -n \
    --arg run_id "$run_id" \
    --arg started_at_utc "$started_at_utc" \
    --arg finished_at_utc "$finished_at_utc" \
    --arg spec_path "$spec_path" \
    --arg tlapm_path "$tlapm_resolved" \
    --arg command "$cmd_quoted" \
    --arg status "$status" \
    --arg stdout_path "$stdout_path" \
    --arg stderr_path "$stderr_path" \
    --argjson duration_ms "$duration_ms" \
    --argjson exit_code "$exit_code" \
    --argjson timed_out "$timed_out_json" \
    --argjson total "$total_json" \
    --argjson proved "$proved_json" \
    --argjson failed "$failed_json" \
    --argjson omitted "$omitted_json" \
    --argjson unknown "$unknown_json" \
    --argjson notes "$notes_json" \
    --argjson stdout_excerpt "$stdout_excerpt_json" \
    --argjson stderr_excerpt "$stderr_excerpt_json" \
    '{
      run_id: $run_id,
      started_at_utc: $started_at_utc,
      finished_at_utc: $finished_at_utc,
      duration_ms: $duration_ms,
      spec_path: $spec_path,
      tlapm_path: $tlapm_path,
      command: $command,
      exit_code: $exit_code,
      timed_out: $timed_out,
      status: $status,
      stdout_path: $stdout_path,
      stderr_path: $stderr_path,
      proof_obligation_counts: {
        total: $total,
        proved: $proved,
        failed: $failed,
        omitted: $omitted,
        unknown: $unknown
      },
      notes: $notes,
      stdout_excerpt: $stdout_excerpt,
      stderr_excerpt: $stderr_excerpt
    }' >"$summary_path"
}

SPEC=""
TLAPM_BIN="tlapm"
TIMEOUT_SECS=0
OUT_ROOT=""
MAX_LINES=200

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec)
      [[ $# -ge 2 ]] || die "missing value for --spec"
      SPEC="$2"
      shift 2
      ;;
    --tlapm)
      [[ $# -ge 2 ]] || die "missing value for --tlapm"
      TLAPM_BIN="$2"
      shift 2
      ;;
    --timeout-secs)
      [[ $# -ge 2 ]] || die "missing value for --timeout-secs"
      TIMEOUT_SECS="$2"
      shift 2
      ;;
    --out-root)
      [[ $# -ge 2 ]] || die "missing value for --out-root"
      OUT_ROOT="$2"
      shift 2
      ;;
    --max-lines)
      [[ $# -ge 2 ]] || die "missing value for --max-lines"
      MAX_LINES="$2"
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

[[ -n "$SPEC" ]] || die "--spec is required"
[[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]] || die "--timeout-secs must be a non-negative integer"
[[ "$MAX_LINES" =~ ^[0-9]+$ ]] || die "--max-lines must be a non-negative integer"

require_cmd jq

spec_path="$(abs_existing_file "$SPEC" || true)"
[[ -n "$spec_path" ]] || die "spec not found: $SPEC"

spec_dir="$(dirname "$spec_path")"
spec_file="$(basename "$spec_path")"

if [[ -n "$OUT_ROOT" ]]; then
  out_root="$(abs_maybe_missing "$OUT_ROOT")"
else
  out_root="$spec_dir/.tla-proof/runs"
fi

mkdir -p "$out_root"
run_id="$(mk_run_id "$spec_path")"
run_dir="$out_root/$run_id"

if ! mkdir "$run_dir" 2>/dev/null; then
  suffix=1
  while [[ "$suffix" -le 99 ]]; do
    run_dir="$out_root/$run_id-$suffix"
    if mkdir "$run_dir" 2>/dev/null; then
      run_id="$run_id-$suffix"
      break
    fi
    suffix=$((suffix + 1))
  done
  [[ -d "$run_dir" ]] || die "unable to create unique run dir under: $out_root"
fi

stdout_path="$run_dir/tlaps.stdout"
stderr_path="$run_dir/tlaps.stderr"
summary_path="$run_dir/summary.json"

started_epoch="$(date +%s)"
started_at_utc="$(iso_utc_now)"
finished_epoch="$started_epoch"
finished_at_utc="$started_at_utc"
duration_ms=0

tlapm_resolved="$(command -v "$TLAPM_BIN" 2>/dev/null || true)"
if [[ -z "$tlapm_resolved" ]]; then
  cmd_quoted="$(quote_cmd "$TLAPM_BIN" "$spec_file")"
  printf 'missing required command: %s\n' "$TLAPM_BIN" >"$stderr_path"
  finished_epoch="$(date +%s)"
  finished_at_utc="$(iso_utc_now)"
  duration_ms=$(( (finished_epoch - started_epoch) * 1000 ))
  write_summary "error" 2 "false"
  printf 'missing required command: %s\n' "$TLAPM_BIN" >&2
  exit 2
fi

cmd=("$tlapm_resolved" "$spec_file")
cmd_quoted="$(quote_cmd "${cmd[@]}")"

timeout_flag="$run_dir/.timed_out"
watchdog_pid=""

(
  cd "$spec_dir"
  "${cmd[@]}"
) >"$stdout_path" 2>"$stderr_path" &
tlapm_pid=$!

if (( TIMEOUT_SECS > 0 )); then
  (
    sleep "$TIMEOUT_SECS"
    if kill -0 "$tlapm_pid" 2>/dev/null; then
      : >"$timeout_flag"
      terminate_process_tree "$tlapm_pid"
    fi
  ) &
  watchdog_pid=$!
fi

if wait "$tlapm_pid" 2>/dev/null; then
  exit_code=0
else
  exit_code=$?
fi

if [[ -n "$watchdog_pid" ]]; then
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
fi

timed_out=false
if [[ -f "$timeout_flag" ]]; then
  timed_out=true
  exit_code=124
fi

finished_epoch="$(date +%s)"
finished_at_utc="$(iso_utc_now)"
duration_ms=$(( (finished_epoch - started_epoch) * 1000 ))

if [[ "$timed_out" == "true" ]]; then
  status="timeout"
elif [[ "$exit_code" -eq 0 ]]; then
  status="pass"
else
  status="fail"
fi

write_summary "$status" "$exit_code" "$timed_out"

if [[ "$timed_out" == "true" ]]; then
  exit 124
fi
exit "$exit_code"
