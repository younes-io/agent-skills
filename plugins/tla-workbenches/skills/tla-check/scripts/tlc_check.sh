#!/usr/bin/env bash
# Author: dev@younes.io
# Maintainer: dev@younes.io
set -euo pipefail

usage() {
  cat <<'EOF'
Run TLC and emit a machine-readable run summary JSON.

Usage:
  tlc_check.sh --spec path/to/Foo.tla [options]

Options:
  --spec PATH           Path to root .tla module (required)
  --cfg PATH            Path to .cfg file (default: <spec>.cfg)
  --jar PATH            Path to tla2tools.jar (default: $TLA2TOOLS_JAR or guessed paths)
  --java BIN            Java executable (default: java)
  --workers N           TLC workers (default: 1)
  --timeout-secs N      Kill TLC after N seconds (default: 0 = no timeout)
  --out-root PATH       Run artifact root (default: <spec-dir>/.tla-check/runs)
  --trace-max-steps N   Max trace steps in counterexample summary (default: 50)
  -h, --help            Show this help
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
  local cfg_path="$2"
  local ts
  local spec_h
  local cfg_h
  ts="$(date '+%Y%m%d-%H%M%S')"
  spec_h="$(sha256_file "$spec_path" 2>/dev/null | cut -c1-8 || true)"
  cfg_h="$(sha256_file "$cfg_path" 2>/dev/null | cut -c1-8 || true)"
  if [[ -n "$spec_h" && -n "$cfg_h" ]]; then
    printf '%s-%s-%s\n' "$ts" "$spec_h" "$cfg_h"
  else
    printf '%s\n' "$ts"
  fi
}

file_mtime() {
  local path="$1"
  if stat -c '%Y' "$path" >/dev/null 2>&1; then
    stat -c '%Y' "$path"
  else
    stat -f '%m' "$path"
  fi
}

pick_metadir() {
  local meta_root="$1"
  local newest=""
  local newest_mtime=0
  local d
  local m
  [[ -d "$meta_root" ]] || return 1
  for d in "$meta_root"/*; do
    [[ -d "$d" ]] || continue
    m="$(file_mtime "$d" 2>/dev/null || printf '0')"
    if [[ -z "$newest" || "$m" -gt "$newest_mtime" ]]; then
      newest="$d"
      newest_mtime="$m"
    fi
  done
  [[ -n "$newest" ]] || return 1
  printf '%s\n' "$newest"
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

find_tla2tools_jar() {
  local spec_dir="$1"
  local explicit="${2:-}"
  local env_jar
  local parent
  local candidate
  local guesses=()

  if [[ -n "$explicit" ]]; then
    candidate="$(expand_user_path "$explicit")"
    if [[ -f "$candidate" ]]; then
      abs_path "$candidate"
      return 0
    fi
    return 1
  fi

  env_jar="${TLA2TOOLS_JAR:-}"
  if [[ -n "$env_jar" ]]; then
    candidate="$(expand_user_path "$env_jar")"
    if [[ -f "$candidate" ]]; then
      abs_path "$candidate"
      return 0
    fi
  fi

  guesses+=("$spec_dir/tla2tools.jar")
  guesses+=("$spec_dir/dist/tla2tools.jar")
  guesses+=("$(pwd -P)/tla2tools.jar")

  parent="$spec_dir"
  while :; do
    guesses+=("$parent/tlatools/org.lamport.tlatools/dist/tla2tools.jar")
    [[ "$parent" == "/" ]] && break
    parent="$(dirname "$parent")"
  done

  for candidate in "${guesses[@]}"; do
    if [[ -f "$candidate" ]]; then
      abs_path "$candidate"
      return 0
    fi
  done
  return 1
}

SPEC=""
CFG=""
JAR=""
JAVA_BIN="java"
WORKERS=1
TIMEOUT_SECS=0
OUT_ROOT=""
TRACE_MAX_STEPS=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec)
      [[ $# -ge 2 ]] || die "missing value for --spec"
      SPEC="$2"
      shift 2
      ;;
    --cfg)
      [[ $# -ge 2 ]] || die "missing value for --cfg"
      CFG="$2"
      shift 2
      ;;
    --jar)
      [[ $# -ge 2 ]] || die "missing value for --jar"
      JAR="$2"
      shift 2
      ;;
    --java)
      [[ $# -ge 2 ]] || die "missing value for --java"
      JAVA_BIN="$2"
      shift 2
      ;;
    --workers)
      [[ $# -ge 2 ]] || die "missing value for --workers"
      WORKERS="$2"
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
    --trace-max-steps)
      [[ $# -ge 2 ]] || die "missing value for --trace-max-steps"
      TRACE_MAX_STEPS="$2"
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
[[ "$WORKERS" =~ ^[0-9]+$ ]] || die "--workers must be a non-negative integer"
[[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]] || die "--timeout-secs must be a non-negative integer"
[[ "$TRACE_MAX_STEPS" =~ ^[0-9]+$ ]] || die "--trace-max-steps must be a non-negative integer"

require_cmd jq
require_cmd "$JAVA_BIN"

spec_path="$(abs_existing_file "$SPEC" || true)"
[[ -n "$spec_path" ]] || die "spec not found: $SPEC"

if [[ -n "$CFG" ]]; then
  cfg_path="$(abs_existing_file "$CFG" || true)"
else
  cfg_path="$(abs_existing_file "${spec_path%.*}.cfg" || true)"
fi
[[ -n "$cfg_path" ]] || die "cfg not found: ${CFG:-${spec_path%.*}.cfg}"

spec_dir="$(dirname "$spec_path")"
module="$(basename "${spec_path%.*}")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

jar_path="$(find_tla2tools_jar "$spec_dir" "$JAR" || true)"
if [[ -z "$jar_path" ]]; then
  cat >&2 <<'EOF'
tla2tools.jar not found. Set $TLA2TOOLS_JAR or pass --jar.
If you're in the tlaplus/tlaplus repo, build it with:
  ant -f tlatools/org.lamport.tlatools/customBuild.xml default-maven
and then use:
  tlatools/org.lamport.tlatools/dist/tla2tools.jar
EOF
  exit 2
fi

if [[ -n "$OUT_ROOT" ]]; then
  out_root="$(abs_maybe_missing "$OUT_ROOT")"
else
  out_root="$spec_dir/.tla-check/runs"
fi

mkdir -p "$out_root"
run_id="$(mk_run_id "$spec_path" "$cfg_path")"
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

stdout_path="$run_dir/tlc.stdout"
stderr_path="$run_dir/tlc.stderr"
summary_path="$run_dir/summary.json"
trace_path="$run_dir/counterexample.json"
meta_root="$run_dir/metadir"
mkdir -p "$meta_root"

if [[ "$(dirname "$cfg_path")" == "$spec_dir" ]]; then
  cfg_arg="$(basename "$cfg_path")"
else
  cfg_arg="$cfg_path"
fi

cmd=(
  "$JAVA_BIN"
  "-cp"
  "$jar_path"
  "tlc2.TLC"
  "-workers"
  "$WORKERS"
  "-metadir"
  "$meta_root"
  "-dumpTrace"
  "json"
  "$trace_path"
  "-config"
  "$cfg_arg"
  "$module"
)

started_epoch="$(date +%s)"
started_at_utc="$(iso_utc_now)"
timeout_flag="$run_dir/.timed_out"
watchdog_pid=""

(
  cd "$spec_dir"
  "${cmd[@]}"
) >"$stdout_path" 2>"$stderr_path" &
tlc_pid=$!

if (( TIMEOUT_SECS > 0 )); then
  (
    sleep "$TIMEOUT_SECS"
    if kill -0 "$tlc_pid" 2>/dev/null; then
      : >"$timeout_flag"
      kill "$tlc_pid" 2>/dev/null || true
      sleep 2
      kill -9 "$tlc_pid" 2>/dev/null || true
    fi
  ) &
  watchdog_pid=$!
fi

if wait "$tlc_pid" 2>/dev/null; then
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

metadir_used="$(pick_metadir "$meta_root" || true)"
trace_exists=false
if [[ -f "$trace_path" ]]; then
  trace_exists=true
fi

if [[ "$trace_exists" == true ]]; then
  status="fail"
elif [[ "$timed_out" == true ]]; then
  status="timeout"
elif [[ "$exit_code" -eq 0 ]]; then
  status="pass"
else
  status="error"
fi

spec_sha256="$(sha256_file "$spec_path" || die "unable to hash spec file: $spec_path")"
cfg_sha256="$(sha256_file "$cfg_path" || die "unable to hash cfg file: $cfg_path")"
command_json="$(printf '%s\n' "${cmd[@]}" | jq -R . | jq -s .)"
command_str="$(quote_cmd "${cmd[@]}")"

counterexample_json_path=""
if [[ "$trace_exists" == true ]]; then
  counterexample_json_path="$trace_path"
fi

summary_json="$(
  jq -n \
    --arg status "$status" \
    --argjson exit_code "$exit_code" \
    --argjson timed_out "$timed_out" \
    --arg started_at_utc "$started_at_utc" \
    --arg finished_at_utc "$finished_at_utc" \
    --argjson duration_ms "$duration_ms" \
    --arg spec_path "$spec_path" \
    --arg cfg_path "$cfg_path" \
    --arg module "$module" \
    --arg spec_dir "$spec_dir" \
    --arg jar_path "$jar_path" \
    --arg spec_sha256 "$spec_sha256" \
    --arg cfg_sha256 "$cfg_sha256" \
    --argjson command "$command_json" \
    --arg command_str "$command_str" \
    --arg run_dir "$run_dir" \
    --arg meta_root "$meta_root" \
    --arg metadir "$metadir_used" \
    --arg stdout_path "$stdout_path" \
    --arg stderr_path "$stderr_path" \
    --arg counterexample_json_path "$counterexample_json_path" \
    '{
      "status": $status,
      "exit_code": $exit_code,
      "timed_out": $timed_out,
      "started_at_utc": $started_at_utc,
      "finished_at_utc": $finished_at_utc,
      "duration_ms": $duration_ms,
      "spec_path": $spec_path,
      "cfg_path": $cfg_path,
      "module": $module,
      "spec_dir": $spec_dir,
      "jar_path": $jar_path,
      "inputs": {
        "spec_sha256": $spec_sha256,
        "cfg_sha256": $cfg_sha256
      },
      "command": $command,
      "command_str": $command_str,
      "run_dir": $run_dir,
      "meta_root": $meta_root,
      "metadir": (if $metadir == "" then null else $metadir end),
      "stdout_path": $stdout_path,
      "stderr_path": $stderr_path,
      "counterexample_json_path": (if $counterexample_json_path == "" then null else $counterexample_json_path end)
    }'
)"

if [[ "$trace_exists" == true ]]; then
  if [[ -x "$script_dir/tlc_trace_summary.sh" ]]; then
    if counterexample_summary_json="$("$script_dir/tlc_trace_summary.sh" --trace "$trace_path" --max-steps "$TRACE_MAX_STEPS" 2>/dev/null)"; then
      summary_json="$(jq --argjson counterexample_summary "$counterexample_summary_json" '. + {"counterexample_summary": $counterexample_summary}' <<<"$summary_json")"
    fi
  fi
fi

pretty_summary="$(jq . <<<"$summary_json")"
printf '%s\n' "$pretty_summary" >"$summary_path"
printf '%s\n' "$pretty_summary"

if [[ "$status" == "pass" ]]; then
  exit 0
fi
if [[ "$status" == "fail" ]]; then
  exit 10
fi
if [[ "$status" == "timeout" ]]; then
  exit 11
fi
exit 12
