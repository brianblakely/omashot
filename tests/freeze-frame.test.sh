#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
STUB_BIN="$TEST_ROOT/bin"
STATE_ROOT="$TEST_ROOT/state"
OUTPUT_DIR="$TEST_ROOT/output"
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

mkdir -p "$STUB_BIN" "$OUTPUT_DIR"

cat >"$STUB_BIN/grim" <<'STUB'
#!/usr/bin/env bash
freeze_pid="${OMASNAP_TEST_EXPECTED_FREEZE_PID:-}"
if [[ -z $freeze_pid && -f ${OMASNAP_TEST_INTERNAL_FREEZE_PID_FILE:-} ]]; then
  freeze_pid=$(<"$OMASNAP_TEST_INTERNAL_FREEZE_PID_FILE")
fi

[[ $freeze_pid =~ ^[1-9][0-9]*$ ]] || exit 90
kill -0 "$freeze_pid" 2>/dev/null || exit 91
printf 'alive\n' >>"$OMASNAP_TEST_GRIM_FREEZE_MARKER"
printf '%s\n' "$*" >>"$OMASNAP_TEST_GRIM_LOG"

if [[ ${OMASNAP_TEST_GRIM_FAIL:-false} == true ]]; then
  exit 7
fi

output=${!#}
printf 'frozen pixels\n' >"$output"
STUB

cat >"$STUB_BIN/hyprpicker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$OMASNAP_TEST_INTERNAL_FREEZE_PID_FILE"
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
    XDG_STATE_HOME="$STATE_ROOT" \
    OMASNAP_TEST_GRIM_LOG="$GRIM_LOG" \
    OMASNAP_TEST_GRIM_FREEZE_MARKER="$GRIM_FREEZE_MARKER" \
    OMASNAP_TEST_INTERNAL_FREEZE_PID_FILE="$INTERNAL_FREEZE_PID_FILE" \
    OMASNAP_TEST_EXPECTED_FREEZE_PID="${OMASNAP_TEST_EXPECTED_FREEZE_PID:-}" \
    OMASNAP_TEST_GRIM_FAIL="${OMASNAP_TEST_GRIM_FAIL:-false}" \
    "$PLUGIN_DIR/omasnap" "$@"
}

sleep 30 &
external_freeze_pid=$!
RUNNING_PIDS+=("$external_freeze_pid")
OMASNAP_TEST_EXPECTED_FREEZE_PID="$external_freeze_pid" \
  run_screenshot screenshot selection \
    --geometry="10,20 30x40" \
    --freeze-pid="$external_freeze_pid" \
    --output-mode=file \
    --save-location="$OUTPUT_DIR" \
    --settle=0 >/dev/null

assert_stopped "$external_freeze_pid" "external freeze survived a successful capture"
[[ -s $GRIM_FREEZE_MARKER ]] || fail "grim did not see the external freeze"
grep -Fq -- '-g 10,20 30x40' "$GRIM_LOG" || fail "grim received the wrong geometry"

rm -f "$INTERNAL_FREEZE_PID_FILE"
OMASNAP_TEST_EXPECTED_FREEZE_PID="" \
  run_screenshot screenshot selection \
    --output-mode=file \
    --save-location="$OUTPUT_DIR" \
    --settle=0 >/dev/null

internal_freeze_pid=$(<"$INTERNAL_FREEZE_PID_FILE")
assert_stopped "$internal_freeze_pid" "picker freeze survived a successful capture"

sleep 30 &
failed_freeze_pid=$!
RUNNING_PIDS+=("$failed_freeze_pid")
if OMASNAP_TEST_EXPECTED_FREEZE_PID="$failed_freeze_pid" OMASNAP_TEST_GRIM_FAIL=true \
  run_screenshot screenshot selection \
    --geometry="1,2 3x4" \
    --freeze-pid="$failed_freeze_pid" \
    --output-mode=file \
    --save-location="$OUTPUT_DIR" \
    --settle=0 >/dev/null; then
  fail "failed grim capture returned success"
fi

assert_stopped "$failed_freeze_pid" "external freeze survived a failed capture"

printf 'PASS: frozen-frame screenshot handoff\n'
