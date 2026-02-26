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
  --out-root PATH      Run artifact root (default: <spec-dir>/.tlaps-workbench/runs)
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

extract_first_number() {
  local file="$1"
  local pattern="$2"
  local line
  local number
  line="$(grep -iE "$pattern" "$file" 2>/dev/null | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 0
  fi
  number="$(printf '%s\n' "$line" | grep -Eo '[0-9]+' | head -n 1 || true)"
  if [[ -n "$number" ]]; then
    printf '%s\n' "$number"
  fi
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
  COUNT_TOTAL=""
  COUNT_PROVED=""
  COUNT_FAILED=""
  COUNT_OMITTED=""
  COUNT_UNKNOWN=""

  if [[ ! -s "$combined" ]]; then
    append_note "No TLAPS output was available for obligation parsing."
    return
  fi

  COUNT_TOTAL="$(extract_first_number "$combined" 'obligation')"
  COUNT_PROVED="$(extract_first_number "$combined" 'proved|discharged|checked')"
  COUNT_FAILED="$(extract_first_number "$combined" 'failed|unproved|not proved|remaining')"
  COUNT_OMITTED="$(extract_first_number "$combined" 'omitted|skipped|unchecked')"

  if [[ -z "$COUNT_TOTAL" ]]; then
    append_note "Could not parse total obligations from TLAPS output."
  fi

  if [[ -z "$COUNT_PROVED" && -z "$COUNT_FAILED" && -z "$COUNT_OMITTED" ]]; then
    append_note "Could not parse proved/failed/omitted obligation counts from TLAPS output."
  fi

  if [[ "$COUNT_TOTAL" =~ ^[0-9]+$ ]]; then
    local subtotal=0
    if [[ "$COUNT_PROVED" =~ ^[0-9]+$ ]]; then
      subtotal=$((subtotal + COUNT_PROVED))
    fi
    if [[ "$COUNT_FAILED" =~ ^[0-9]+$ ]]; then
      subtotal=$((subtotal + COUNT_FAILED))
    fi
    if [[ "$COUNT_OMITTED" =~ ^[0-9]+$ ]]; then
      subtotal=$((subtotal + COUNT_OMITTED))
    fi
    if (( COUNT_TOTAL >= subtotal )); then
      COUNT_UNKNOWN=$((COUNT_TOTAL - subtotal))
    else
      COUNT_UNKNOWN=0
      append_note "Parsed counts exceeded parsed total obligations; set unknown=0."
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
    head -n "$MAX_LINES" "$stdout_path" >>"$combined" || true
  fi
  if [[ -f "$stderr_path" ]]; then
    head -n "$MAX_LINES" "$stderr_path" >>"$combined" || true
  fi

  NOTES=()
  if (( MAX_LINES == 0 )); then
    append_note "--max-lines is 0; excerpts and parsing input are empty by configuration."
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
  out_root="$spec_dir/.tlaps-workbench/runs"
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
  write_summary "error" 127 "false"
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
      kill "$tlapm_pid" 2>/dev/null || true
      sleep 2
      kill -9 "$tlapm_pid" 2>/dev/null || true
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
