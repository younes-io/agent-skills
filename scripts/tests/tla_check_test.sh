#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s --jar path/to/tla2tools.jar\n' "${0##*/}"
}

jar=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jar)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      jar="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

[[ -n "$jar" ]] || { usage >&2; exit 2; }
[[ -f "$jar" ]] || { printf 'tla2tools.jar not found: %s\n' "$jar" >&2; exit 2; }
command -v java >/dev/null 2>&1 || { printf 'missing required command: java\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'missing required command: jq\n' >&2; exit 2; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
runner="$repo_root/skills/tla-check/scripts/tlc_check.sh"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/tla-check-test.XXXXXX")"
child_pid_file="$tmp_root/timeout-child.pid"

cleanup() {
  if [[ -f "$child_pid_file" ]]; then
    child_pid="$(cat "$child_pid_file" 2>/dev/null || true)"
    [[ -z "$child_pid" ]] || kill -9 "$child_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_root"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_json() {
  local path="$1"
  local filter="$2"
  local message="$3"
  jq -e "$filter" "$path" >/dev/null || fail "$message"
}

summary_under() {
  local root="$1"
  local summary
  summary="$(find "$root" -name summary.json -type f | head -n 1 || true)"
  [[ -n "$summary" ]] || fail "missing summary.json under $root"
  printf '%s\n' "$summary"
}

fixture="$tmp_root/fake"
mkdir -p "$fixture"
printf '%s\n' '---- MODULE Spec ----' 'Init == TRUE' 'Next == FALSE' '====' >"$fixture/Spec.tla"
printf '%s\n' 'INIT Init' 'NEXT Next' >"$fixture/Spec.cfg"
: >"$fixture/tla2tools.jar"

fake_java="$fixture/java"
cat >"$fake_java" <<'FAKE_JAVA'
#!/usr/bin/env bash
set -euo pipefail

case "${FAKE_TLC_MODE:-pass}" in
  pass)
    printf '%s\n' \
      '@!@!@STARTMSG 2193:0 @!@!@' \
      'Model checking completed. No error has been found.' \
      '@!@!@ENDMSG 2193 @!@!@'
    ;;
  error)
    printf 'TLC internal error\n' >&2
    exit 3
    ;;
  counterexample)
    printf '%s\n' \
      '@!@!@STARTMSG 2110:1 @!@!@' \
      'Invariant Safety is violated.' \
      '@!@!@ENDMSG 2110 @!@!@' \
      '@!@!@STARTMSG 2217:4 @!@!@' \
      '1: <Initial predicate>' \
      '/\ x = 0' \
      '@!@!@ENDMSG 2217 @!@!@' \
      '@!@!@STARTMSG 2217:4 @!@!@' \
      '2: <Increment line 1, col 1 to line 1, col 2 of module Spec>' \
      '/\ x = 1' \
      '@!@!@ENDMSG 2217 @!@!@'
    ;;
  malformed)
    printf '%s\n' \
      '@!@!@STARTMSG 2217:4 @!@!@' \
      'not a state' \
      '@!@!@ENDMSG 2217 @!@!@'
    ;;
  timeout)
    (sleep 30) &
    child_pid=$!
    printf '%s\n' "$child_pid" >"$FAKE_TLC_CHILD_PID_FILE"
    wait "$child_pid"
    ;;
esac
FAKE_JAVA
chmod +x "$fake_java"

run_fake() {
  local mode="$1"
  local expected_exit="$2"
  local out_root="$tmp_root/fake-$mode"
  local actual_exit
  local extra_args=()

  if [[ "$mode" == timeout ]]; then
    extra_args+=(--timeout-secs 1)
  fi

  set +e
  FAKE_TLC_MODE="$mode" FAKE_TLC_CHILD_PID_FILE="$child_pid_file" \
    "$runner" \
      --spec "$fixture/Spec.tla" \
      --cfg "$fixture/Spec.cfg" \
      --jar "$fixture/tla2tools.jar" \
      --java "$fake_java" \
      --out-root "$out_root" \
      ${extra_args[@]+"${extra_args[@]}"} \
      >/dev/null 2>&1
  actual_exit=$?
  set -e

  [[ "$actual_exit" -eq "$expected_exit" ]] || fail "$mode expected exit $expected_exit, got $actual_exit"
  summary_under "$out_root"
}

pass_summary="$(run_fake pass 0)"
assert_json "$pass_summary" '.status == "pass" and (.command | any(. == "-tool"))' "fake pass classification"

error_summary="$(run_fake error 12)"
assert_json "$error_summary" '.status == "error" and .exit_code == 3' "fake error classification"

counterexample_summary="$(run_fake counterexample 10)"
assert_json "$counterexample_summary" '
  .status == "fail" and
  .counterexample_summary.states_total == 2 and
  .counterexample_summary.steps[1].action.name == "Increment"
' "counterexample conversion"

malformed_summary="$(run_fake malformed 12)"
assert_json "$malformed_summary" '.status == "error" and .counterexample_json_path == null' "malformed trace classification"

timeout_summary="$(run_fake timeout 11)"
assert_json "$timeout_summary" '.status == "timeout" and .timed_out == true and .exit_code == 124' "timeout classification"
child_pid="$(cat "$child_pid_file")"
sleep 1
kill -0 "$child_pid" 2>/dev/null && fail "timeout left a descendant process running"

real_fixture="$tmp_root/real"
mkdir -p "$real_fixture"
cat >"$real_fixture/Flawed.tla" <<'EOF'
------------------------------ MODULE Flawed ------------------------------
EXTENDS Naturals
VARIABLE x
Vars == <<x>>
Init == x = 0
Next == /\ x = 0 /\ x' = 1
Safety == x = 0
Spec == Init /\ [][Next]_Vars
=============================================================================
EOF
cat >"$real_fixture/Flawed.cfg" <<'EOF'
SPECIFICATION Spec
INVARIANT Safety
CHECK_DEADLOCK FALSE
EOF
cat >"$real_fixture/Fixed.tla" <<'EOF'
------------------------------- MODULE Fixed -------------------------------
EXTENDS Naturals
VARIABLE x
Vars == <<x>>
Init == x = 0
Next == /\ x = 0 /\ x' = 1
Safety == x \in 0..1
Spec == Init /\ [][Next]_Vars
=============================================================================
EOF
cat >"$real_fixture/Fixed.cfg" <<'EOF'
SPECIFICATION Spec
INVARIANT Safety
CHECK_DEADLOCK FALSE
EOF

run_real() {
  local module="$1"
  local expected_exit="$2"
  local out_root="$tmp_root/real-$module"
  local output="$tmp_root/$module.summary.json"
  local actual_exit

  set +e
  "$runner" \
    --spec "$real_fixture/$module.tla" \
    --cfg "$real_fixture/$module.cfg" \
    --jar "$jar" \
    --workers 1 \
    --out-root "$out_root" >"$output"
  actual_exit=$?
  set -e

  [[ "$actual_exit" -eq "$expected_exit" ]] || fail "$module expected exit $expected_exit, got $actual_exit"
  printf '%s\n' "$output"
}

flawed_summary="$(run_real Flawed 10)"
assert_json "$flawed_summary" '.status == "fail" and .counterexample_summary.states_total == 2' "real counterexample"

fixed_summary="$(run_real Fixed 0)"
assert_json "$fixed_summary" '.status == "pass" and .counterexample_json_path == null' "real passing model"

printf 'PASS: tla-check behavioral tests\n'
