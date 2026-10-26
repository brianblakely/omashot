#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
STUB_BIN="$TEST_ROOT/bin"
STATE_ROOT="$TEST_ROOT/state"
RECORDING_MARKER="$TEST_ROOT/recording-marker"
OMACUT_LOG="$TEST_ROOT/omacut-args"
STOP_STDOUT="$TEST_ROOT/stop-stdout"
INJECTION_SENTINEL="$TEST_ROOT/command-injection-ran"
TEST_HOME="$TEST_ROOT/home"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" message="$3"
  [[ $actual == "$expected" ]] ||
    fail "$message (expected '$expected', got '$actual')"
}

run_omashot() {
  (
    cd "$TEST_ROOT"
    env \
      PATH="$STUB_BIN:$PATH" \
      HOME="$TEST_HOME" \
      XDG_STATE_HOME="$STATE_ROOT" \
      TEST_RECORDING_MARKER="$RECORDING_MARKER" \
      TEST_OMACUT_LOG="$OMACUT_LOG" \
      TEST_FINALIZE_FILE="${TEST_FINALIZE_FILE:-}" \
      TEST_STOP_OUTPUT="${TEST_STOP_OUTPUT:-}" \
      TEST_STOP_STATUS="${TEST_STOP_STATUS:-0}" \
      "$PLUGIN_DIR/omashot" stop-recording
  )
}

mkdir -p "$STUB_BIN" "$TEST_HOME/.config/omarchy"

jq -n '{version: 1, plugins: [{id: "b.omashot"}]}' \
  >"$TEST_HOME/.config/omarchy/shell.json"

cat >"$STUB_BIN/omarchy-capture-screenrecording" <<'STUB'
#!/usr/bin/env bash
if [[ -n ${TEST_FINALIZE_FILE:-} ]]; then
  printf 'video data\n' >"$TEST_FINALIZE_FILE"
fi
if [[ ${1:-} == --stop-recording && -n ${TEST_STOP_OUTPUT:-} ]]; then
  printf '%s\n' "$TEST_STOP_OUTPUT"
fi
rm -f "$TEST_RECORDING_MARKER"
exit "${TEST_STOP_STATUS:-0}"
STUB

cat >"$STUB_BIN/cat" <<'STUB'
#!/usr/bin/env bash
# The marker lives in the per-user runtime dir; match it by basename so the
# test does not have to know which runtime directory the helper picked.
if [[ $# == 1 && ${1##*/} == omarchy-screenrecord-filename ]]; then
  exec /usr/bin/cat "$TEST_RECORDING_MARKER"
fi
exec /usr/bin/cat "$@"
STUB

cat >"$STUB_BIN/setsid" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB

cat >"$STUB_BIN/uwsm-app" <<'STUB'
#!/usr/bin/env bash
[[ ${1:-} == -- ]] && shift
exec "$@"
STUB

cat >"$STUB_BIN/omacut" <<'STUB'
#!/usr/bin/env bash
# Records any launch. Nothing should reach this during a stop: the card the
# stop posts is the only way into the recording.
printf '%s\0' "$#" "$@" >"$TEST_OMACUT_LOG"
STUB

chmod +x "$STUB_BIN"/*

recording="$TEST_ROOT/screen recording \$(touch command-injection-ran);'\".mp4"
touch "$recording"
printf '%s\n' "$recording" >"$RECORDING_MARKER"
TEST_FINALIZE_FILE="$recording" TEST_STOP_OUTPUT="$recording" \
  run_omashot >"$STOP_STDOUT"

assert_equal "$recording" "$(sed -n '1p' "$STOP_STDOUT")" \
  "stop output was not forwarded"

# The recording must not open by itself: the card it posts is the way in, so a
# finished recording leaves the screen as it was.
[[ ! -e $OMACUT_LOG ]] || fail "the recording opened itself instead of waiting for the card"
[[ ! -e $INJECTION_SENTINEL ]] || fail "recording path was evaluated as shell code"
assert_equal "$recording" \
  "$(jq -r '.lastRecording' "$STATE_ROOT/omashot/state.json")" \
  "completed recording was not saved in Omashot state"

rm -f "$OMACUT_LOG"
printf '%s\n' "$recording" >"$RECORDING_MARKER"
if TEST_FINALIZE_FILE="$recording" TEST_STOP_OUTPUT="$recording" \
  TEST_STOP_STATUS=7 run_omashot >/dev/null; then
  fail "failed stop returned success"
else
  assert_equal "7" "$?" "failed stop status was not preserved"
fi
[[ ! -e $OMACUT_LOG ]] || fail "Omacut opened after a failed stop"

printf '%s\n' "$recording" >"$RECORDING_MARKER"
TEST_FINALIZE_FILE="$recording" TEST_STOP_OUTPUT="" \
  run_omashot >/dev/null
[[ ! -e $OMACUT_LOG ]] || fail "Omacut opened without finalized-path output"

missing_recording="$TEST_ROOT/missing recording.mp4"
printf '%s\n' "$missing_recording" >"$RECORDING_MARKER"
TEST_STOP_OUTPUT="$missing_recording" run_omashot >/dev/null
[[ ! -e $OMACUT_LOG ]] || fail "Omacut opened a missing recording"

printf 'PASS: completed recording handoff\n'
