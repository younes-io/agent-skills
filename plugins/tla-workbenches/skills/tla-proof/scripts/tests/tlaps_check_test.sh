#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
runner="$script_dir/../tlaps_check.sh"

if [[ ! -f "$runner" ]]; then
  printf 'test setup error: runner not found at %s\n' "$runner" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'test setup error: jq is required\n' >&2
  exit 2
fi

tmp_parent="${TLAPS_CHECK_TEST_TMPDIR:-$script_dir/../../../../.tmp-tlaps-check-test}"
mkdir -p "$tmp_parent"
tmp_root="$(mktemp -d "$tmp_parent/run.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
  rmdir "$tmp_parent" 2>/dev/null || true
}
trap cleanup EXIT

spec_path="$tmp_root/Spec.tla"
cat >"$spec_path" <<'SPEC'
---- MODULE Spec ----
THEOREM Dummy == TRUE
====
SPEC

wrappers_dir="$tmp_root/wrappers"
runs_dir="$tmp_root/runs"
mkdir -p "$wrappers_dir" "$runs_dir"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    fail "$message (expected: $expected, actual: $actual)"
  fi
}

assert_json_eq() {
  local expected="$1"
  local jq_filter="$2"
  local json_path="$3"
  local message="$4"
  local actual
  actual="$(jq -r "$jq_filter" "$json_path")"
  assert_eq "$expected" "$actual" "$message"
}

summary_for_case() {
  local case_root="$1"
  local summary
  summary="$(find "$case_root" -name summary.json -type f | head -n 1 || true)"
  if [[ -z "$summary" || ! -f "$summary" ]]; then
    fail "missing summary.json under $case_root"
  fi
  printf '%s\n' "$summary"
}

RUN_EXIT=0
RUN_SUMMARY=""
run_case() {
  local case_name="$1"
  shift
  local case_root="$runs_dir/$case_name"
  mkdir -p "$case_root"

  set +e
  "$runner" --spec "$spec_path" --out-root "$case_root" "$@" >/dev/null 2>&1
  RUN_EXIT=$?
  set -e

  RUN_SUMMARY="$(summary_for_case "$case_root")"
}

run_real_case() {
  local case_name="$1"
  local module_name="$2"
  local module_body="$3"
  local case_root="$runs_dir/$case_name"
  local spec_dir="$tmp_root/$case_name-spec"
  mkdir -p "$case_root" "$spec_dir"

  spec_path="$spec_dir/$module_name.tla"
  printf '%s\n' "$module_body" >"$spec_path"

  set +e
  "$runner" --spec "$spec_path" --out-root "$case_root" >/dev/null 2>&1
  RUN_EXIT=$?
  set -e

  RUN_SUMMARY="$(summary_for_case "$case_root")"
}

wrapper_pass="$wrappers_dir/pass.sh"
cat >"$wrapper_pass" <<'EOF_WRAPPER_PASS'
#!/usr/bin/env bash
set -euo pipefail
echo "Summary: total obligations: 3 proved: 3 failed: 0 omitted: 0"
exit 0
EOF_WRAPPER_PASS
chmod +x "$wrapper_pass"

wrapper_mixed="$wrappers_dir/mixed.sh"
cat >"$wrapper_mixed" <<'EOF_WRAPPER_MIXED'
#!/usr/bin/env bash
set -euo pipefail
echo "Progress: checked 10 of 40 obligations"
echo "Summary: total obligations: 40 proved: 39 failed: 1 omitted: 0"
exit 1
EOF_WRAPPER_MIXED
chmod +x "$wrapper_mixed"

wrapper_progress_only="$wrappers_dir/progress_only.sh"
cat >"$wrapper_progress_only" <<'EOF_WRAPPER_PROGRESS'
#!/usr/bin/env bash
set -euo pipefail
echo "Progress: checked 10 of 40 obligations"
exit 1
EOF_WRAPPER_PROGRESS
chmod +x "$wrapper_progress_only"

wrapper_real_tlapm_style="$wrappers_dir/real_tlapm_style.sh"
cat >"$wrapper_real_tlapm_style" <<'EOF_WRAPPER_REAL_TLAPM'
#!/usr/bin/env bash
set -euo pipefail
echo '(* created new ".tlacache/Trivial.tlaps/Trivial.thy" *)'
echo '[INFO]: All 1 obligation proved.' >&2
exit 0
EOF_WRAPPER_REAL_TLAPM
chmod +x "$wrapper_real_tlapm_style"

wrapper_real_tlapm_fail_style="$wrappers_dir/real_tlapm_fail_style.sh"
cat >"$wrapper_real_tlapm_fail_style" <<'EOF_WRAPPER_REAL_TLAPM_FAIL'
#!/usr/bin/env bash
set -euo pipefail
echo 'Zenon error: exhausted search space without finding a proof'
echo '[ERROR]: 1/1 obligation failed.' >&2
exit 3
EOF_WRAPPER_REAL_TLAPM_FAIL
chmod +x "$wrapper_real_tlapm_fail_style"

wrapper_timeout_child="$wrappers_dir/timeout_child.sh"
cat >"$wrapper_timeout_child" <<'EOF_WRAPPER_TIMEOUT'
#!/usr/bin/env bash
set -euo pipefail
(sleep 30) &
child_pid=$!
if [[ -n "${TLAPS_CHILD_PID_FILE:-}" ]]; then
  printf '%s\n' "$child_pid" > "$TLAPS_CHILD_PID_FILE"
fi
wait "$child_pid"
EOF_WRAPPER_TIMEOUT
chmod +x "$wrapper_timeout_child"

# Case 1: pass status and exact counts.
run_case pass --tlapm "$wrapper_pass"
assert_eq "0" "$RUN_EXIT" "pass case exit code"
assert_json_eq "pass" '.status' "$RUN_SUMMARY" "pass case status"
assert_json_eq "3" '.proof_obligation_counts.total' "$RUN_SUMMARY" "pass case total"
assert_json_eq "3" '.proof_obligation_counts.proved' "$RUN_SUMMARY" "pass case proved"
assert_json_eq "0" '.proof_obligation_counts.failed' "$RUN_SUMMARY" "pass case failed"
assert_json_eq "0" '.proof_obligation_counts.omitted' "$RUN_SUMMARY" "pass case omitted"
assert_json_eq "0" '.proof_obligation_counts.unknown' "$RUN_SUMMARY" "pass case unknown"

# Case 2: mixed progress + late summary should parse final summary even when excerpts are truncated.
run_case mixed --tlapm "$wrapper_mixed" --max-lines 1
assert_eq "1" "$RUN_EXIT" "mixed case exit code"
assert_json_eq "fail" '.status' "$RUN_SUMMARY" "mixed case status"
assert_json_eq "40" '.proof_obligation_counts.total' "$RUN_SUMMARY" "mixed case total"
assert_json_eq "39" '.proof_obligation_counts.proved' "$RUN_SUMMARY" "mixed case proved"
assert_json_eq "1" '.proof_obligation_counts.failed' "$RUN_SUMMARY" "mixed case failed"
assert_json_eq "0" '.proof_obligation_counts.omitted' "$RUN_SUMMARY" "mixed case omitted"
assert_json_eq "0" '.proof_obligation_counts.unknown' "$RUN_SUMMARY" "mixed case unknown"
assert_json_eq "1" '.stdout_excerpt | length' "$RUN_SUMMARY" "mixed case excerpt length"

# Case 3: progress-only output is treated as untrustworthy for final counts.
run_case progress_only --tlapm "$wrapper_progress_only"
assert_eq "1" "$RUN_EXIT" "progress-only case exit code"
assert_json_eq "null" '.proof_obligation_counts.total' "$RUN_SUMMARY" "progress-only total"
assert_json_eq "null" '.proof_obligation_counts.proved' "$RUN_SUMMARY" "progress-only proved"
assert_json_eq "null" '.proof_obligation_counts.failed' "$RUN_SUMMARY" "progress-only failed"
assert_json_eq "null" '.proof_obligation_counts.omitted' "$RUN_SUMMARY" "progress-only omitted"
assert_json_eq "null" '.proof_obligation_counts.unknown' "$RUN_SUMMARY" "progress-only unknown"
if ! jq -e '.notes[] | contains("progress-style obligation counts")' "$RUN_SUMMARY" >/dev/null; then
  fail "progress-only case note about progress-style parsing"
fi

# Case 4: missing tlapm should keep process and summary exit codes consistent.
run_case missing_tlapm --tlapm "$tmp_root/no-such-tlapm"
assert_eq "2" "$RUN_EXIT" "missing tlapm exit code"
assert_json_eq "error" '.status' "$RUN_SUMMARY" "missing tlapm status"
assert_json_eq "2" '.exit_code' "$RUN_SUMMARY" "missing tlapm summary exit code"

# Case 5: parse TLAPM's real "All N obligation proved" summary style from stderr.
run_case real_tlapm_style --tlapm "$wrapper_real_tlapm_style"
assert_eq "0" "$RUN_EXIT" "real tlapm style exit code"
assert_json_eq "pass" '.status' "$RUN_SUMMARY" "real tlapm style status"
assert_json_eq "1" '.proof_obligation_counts.total' "$RUN_SUMMARY" "real tlapm style total"
assert_json_eq "1" '.proof_obligation_counts.proved' "$RUN_SUMMARY" "real tlapm style proved"
assert_json_eq "0" '.proof_obligation_counts.failed' "$RUN_SUMMARY" "real tlapm style failed"
assert_json_eq "0" '.proof_obligation_counts.omitted' "$RUN_SUMMARY" "real tlapm style omitted"
assert_json_eq "0" '.proof_obligation_counts.unknown' "$RUN_SUMMARY" "real tlapm style unknown"

# Case 6: parse TLAPM's real "N/N obligation failed" summary style from stderr.
run_case real_tlapm_fail_style --tlapm "$wrapper_real_tlapm_fail_style"
assert_eq "3" "$RUN_EXIT" "real tlapm fail style exit code"
assert_json_eq "fail" '.status' "$RUN_SUMMARY" "real tlapm fail style status"
assert_json_eq "1" '.proof_obligation_counts.total' "$RUN_SUMMARY" "real tlapm fail style total"
assert_json_eq "0" '.proof_obligation_counts.proved' "$RUN_SUMMARY" "real tlapm fail style proved"
assert_json_eq "1" '.proof_obligation_counts.failed' "$RUN_SUMMARY" "real tlapm fail style failed"
assert_json_eq "0" '.proof_obligation_counts.omitted' "$RUN_SUMMARY" "real tlapm fail style omitted"
assert_json_eq "0" '.proof_obligation_counts.unknown' "$RUN_SUMMARY" "real tlapm fail style unknown"

# Case 7: timeout should terminate descendants too.
case_root="$runs_dir/timeout"
mkdir -p "$case_root"
child_pid_file="$tmp_root/timeout-child.pid"
set +e
TLAPS_CHILD_PID_FILE="$child_pid_file" "$runner" --spec "$spec_path" --out-root "$case_root" --tlapm "$wrapper_timeout_child" --timeout-secs 1 >/dev/null 2>&1
timeout_exit=$?
set -e

timeout_summary="$(summary_for_case "$case_root")"
assert_eq "124" "$timeout_exit" "timeout case exit code"
assert_json_eq "timeout" '.status' "$timeout_summary" "timeout case status"
assert_json_eq "true" '.timed_out' "$timeout_summary" "timeout case timed_out"

if [[ ! -f "$child_pid_file" ]]; then
  fail "timeout case did not report spawned child pid"
fi
child_pid="$(cat "$child_pid_file")"
if [[ -z "$child_pid" ]]; then
  fail "timeout case child pid file was empty"
fi
sleep 1
if kill -0 "$child_pid" 2>/dev/null; then
  fail "timeout case child process still alive after timeout cleanup"
fi

if command -v tlapm >/dev/null 2>&1; then
  # Case 6: real tlapm pass output should produce trustworthy counts.
  run_real_case \
    real_tlapm_equiv_pass \
    FormulaEquiv \
'---- MODULE FormulaEquiv ----
F == TRUE /\ TRUE
G == TRUE

THEOREM FormulaEquiv == F <=> G
BY DEF F, G
===='
  assert_eq "0" "$RUN_EXIT" "real tlapm pass exit code"
  assert_json_eq "pass" '.status' "$RUN_SUMMARY" "real tlapm pass status"
  assert_json_eq "1" '.proof_obligation_counts.total' "$RUN_SUMMARY" "real tlapm pass total"
  assert_json_eq "1" '.proof_obligation_counts.proved' "$RUN_SUMMARY" "real tlapm pass proved"
  assert_json_eq "0" '.proof_obligation_counts.failed' "$RUN_SUMMARY" "real tlapm pass failed"
  assert_json_eq "0" '.proof_obligation_counts.omitted' "$RUN_SUMMARY" "real tlapm pass omitted"
  assert_json_eq "0" '.proof_obligation_counts.unknown' "$RUN_SUMMARY" "real tlapm pass unknown"

  # Case 7: real tlapm fail output should produce trustworthy counts.
  run_real_case \
    real_tlapm_equiv_fail \
    FormulaEquivFail \
'---- MODULE FormulaEquivFail ----
F == TRUE
G == FALSE

THEOREM FormulaEquivFail == F <=> G
BY DEF F, G
===='
  assert_eq "3" "$RUN_EXIT" "real tlapm fail exit code"
  assert_json_eq "fail" '.status' "$RUN_SUMMARY" "real tlapm fail status"
  assert_json_eq "1" '.proof_obligation_counts.total' "$RUN_SUMMARY" "real tlapm fail total"
  assert_json_eq "0" '.proof_obligation_counts.proved' "$RUN_SUMMARY" "real tlapm fail proved"
  assert_json_eq "1" '.proof_obligation_counts.failed' "$RUN_SUMMARY" "real tlapm fail failed"
  assert_json_eq "0" '.proof_obligation_counts.omitted' "$RUN_SUMMARY" "real tlapm fail omitted"
  assert_json_eq "0" '.proof_obligation_counts.unknown' "$RUN_SUMMARY" "real tlapm fail unknown"
fi

printf 'PASS: tlaps_check.sh regression tests\n'
