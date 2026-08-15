#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
STUB_BIN="$TEST_ROOT/bin"
STATE_ROOT="$TEST_ROOT/state"
OUTPUT_DIR="$TEST_ROOT/output"
TEST_HOME="$TEST_ROOT/home"
GRIM_LOG="$TEST_ROOT/grim-log"
GRIM_FREEZE_MARKER="$TEST_ROOT/grim-saw-freeze"
INTERNAL_FREEZE_PID_FILE="$TEST_ROOT/internal-freeze-pid"
RUNNING_PIDS=()

cleanup() {
  local pid
  for pid in "${RUNNING_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_stopped() {
  local pid="$1" message="$2" attempt state

  for ((attempt = 0; attempt < 40; attempt++)); do
    state=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]') || state=""
    if [[ -z $state || $state == Z* ]]; then
      wait "$pid" 2>/dev/null || true
      return
    fi
    sleep 0.05
  done

  fail "$message"
}

mkdir -p "$STUB_BIN" "$OUTPUT_DIR" "$TEST_HOME/.config/omarchy"

jq -n --arg output "$OUTPUT_DIR" '{
  version: 1,
  plugins: [{
    id: "b.omashot",
    outputMode: "file",
    saveLocation: $output,
    timerSeconds: 0
  }]
}' >"$TEST_HOME/.config/omarchy/shell.json"

cat >"$STUB_BIN/grim" <<'STUB'
#!/usr/bin/env bash
freeze_pid="${TEST_EXPECTED_FREEZE_PID:-}"
if [[ -z $freeze_pid && -f ${TEST_INTERNAL_FREEZE_PID_FILE:-} ]]; then
  freeze_pid=$(<"$TEST_INTERNAL_FREEZE_PID_FILE")
fi

[[ $freeze_pid =~ ^[1-9][0-9]*$ ]] || exit 90
kill -0 "$freeze_pid" 2>/dev/null || exit 91
printf 'alive\n' >>"$TEST_GRIM_FREEZE_MARKER"
printf '%s\n' "$*" >>"$TEST_GRIM_LOG"

if [[ ${TEST_GRIM_FAIL:-false} == true ]]; then
  exit 7
fi

output=${!#}
printf 'frozen pixels\n' >"$output"
STUB

cat >"$STUB_BIN/hyprpicker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$TEST_INTERNAL_FREEZE_PID_FILE"
exec sleep 30
STUB

cat >"$STUB_BIN/slurp" <<'STUB'
#!/usr/bin/env bash
printf '5,6 70x80\n'
STUB

cat >"$STUB_BIN/hyprctl" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB

cat >"$STUB_BIN/notify-send" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

chmod +x "$STUB_BIN"/*

run_screenshot() {
  env \
    PATH="$STUB_BIN:$PATH" \
    HOME="$TEST_HOME" \
    XDG_STATE_HOME="$STATE_ROOT" \
    TEST_GRIM_LOG="$GRIM_LOG" \
    TEST_GRIM_FREEZE_MARKER="$GRIM_FREEZE_MARKER" \
    TEST_INTERNAL_FREEZE_PID_FILE="$INTERNAL_FREEZE_PID_FILE" \
    TEST_EXPECTED_FREEZE_PID="${TEST_EXPECTED_FREEZE_PID:-}" \
    TEST_GRIM_FAIL="${TEST_GRIM_FAIL:-false}" \
    "$PLUGIN_DIR/omashot" "$@"
}

sleep 30 &
external_freeze_pid=$!
RUNNING_PIDS+=("$external_freeze_pid")
context=$(jq -cn --arg geometry "10,20 30x40" --argjson freezePid "$external_freeze_pid" \
  '{geometry:$geometry,freezePid:$freezePid}')
TEST_EXPECTED_FREEZE_PID="$external_freeze_pid" \
  run_screenshot screenshot selection "$context" >/dev/null

assert_stopped "$external_freeze_pid" "external freeze survived a successful capture"
[[ -s $GRIM_FREEZE_MARKER ]] || fail "grim did not see the external freeze"
grep -Fq -- '-g 10,20 30x40' "$GRIM_LOG" || fail "grim received the wrong geometry"

rm -f "$INTERNAL_FREEZE_PID_FILE"
TEST_EXPECTED_FREEZE_PID="" \
  run_screenshot screenshot selection '{}' >/dev/null

internal_freeze_pid=$(<"$INTERNAL_FREEZE_PID_FILE")
assert_stopped "$internal_freeze_pid" "picker freeze survived a successful capture"

sleep 30 &
failed_freeze_pid=$!
RUNNING_PIDS+=("$failed_freeze_pid")
context=$(jq -cn --arg geometry "1,2 3x4" --argjson freezePid "$failed_freeze_pid" \
  '{geometry:$geometry,freezePid:$freezePid}')
if TEST_EXPECTED_FREEZE_PID="$failed_freeze_pid" TEST_GRIM_FAIL=true \
  run_screenshot screenshot selection "$context" >/dev/null; then
  fail "failed grim capture returned success"
fi

assert_stopped "$failed_freeze_pid" "external freeze survived a failed capture"

printf 'PASS: frozen-frame screenshot handoff\n'
