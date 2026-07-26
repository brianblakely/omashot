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
STOP_COMPLETE="$TEST_ROOT/stop-complete"
ORDERING_ERROR="$TEST_ROOT/opened-before-finalization"

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

wait_for_file() {
  local file="$1"
  local attempt

  for ((attempt = 0; attempt < 40; attempt++)); do
    [[ -f $file ]] && return 0
    sleep 0.05
  done

  fail "timed out waiting for $file"
}

run_omasnap() {
  (
    cd "$TEST_ROOT"
    env \
      PATH="$STUB_BIN:$PATH" \
      XDG_STATE_HOME="$STATE_ROOT" \
      OMASNAP_TEST_RECORDING_MARKER="$RECORDING_MARKER" \
      OMASNAP_TEST_OMACUT_LOG="$OMACUT_LOG" \
      OMASNAP_TEST_STOP_COMPLETE="$STOP_COMPLETE" \
      OMASNAP_TEST_ORDERING_ERROR="$ORDERING_ERROR" \
      OMASNAP_TEST_FINALIZE_FILE="${OMASNAP_TEST_FINALIZE_FILE:-}" \
      OMASNAP_TEST_STOP_OUTPUT="${OMASNAP_TEST_STOP_OUTPUT:-}" \
      OMASNAP_TEST_STOP_STATUS="${OMASNAP_TEST_STOP_STATUS:-0}" \
      "$PLUGIN_DIR/omasnap" stop-recording
  )
}

mkdir -p "$STUB_BIN"

cat >"$STUB_BIN/omarchy-capture-screenrecording" <<'STUB'
#!/usr/bin/env bash
if [[ -n ${OMASNAP_TEST_FINALIZE_FILE:-} ]]; then
  printf 'video data\n' >"$OMASNAP_TEST_FINALIZE_FILE"
  printf 'complete\n' >"$OMASNAP_TEST_STOP_COMPLETE"
fi
if [[ ${1:-} == --stop-recording && -n ${OMASNAP_TEST_STOP_OUTPUT:-} ]]; then
  printf '%s\n' "$OMASNAP_TEST_STOP_OUTPUT"
fi
rm -f "$OMASNAP_TEST_RECORDING_MARKER"
exit "${OMASNAP_TEST_STOP_STATUS:-0}"
STUB

cat >"$STUB_BIN/cat" <<'STUB'
#!/usr/bin/env bash
if [[ $# == 1 && $1 == /tmp/omarchy-screenrecord-filename ]]; then
  exec /usr/bin/cat "$OMASNAP_TEST_RECORDING_MARKER"
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
if [[ ! -f $OMASNAP_TEST_STOP_COMPLETE ]]; then
  printf 'opened too early\n' >"$OMASNAP_TEST_ORDERING_ERROR"
  exit 1
fi
tmp_log="${OMASNAP_TEST_OMACUT_LOG}.tmp.$$"
{
  printf '%s\0' "$#"
  printf '%s\0' "$@"
} >"$tmp_log"
mv "$tmp_log" "$OMASNAP_TEST_OMACUT_LOG"
STUB

chmod +x "$STUB_BIN"/*

recording="$TEST_ROOT/screen recording \$(touch command-injection-ran);'\".mp4"
touch "$recording"
printf '%s\n' "$recording" >"$RECORDING_MARKER"
OMASNAP_TEST_FINALIZE_FILE="$recording" OMASNAP_TEST_STOP_OUTPUT="$recording" \
  run_omasnap >"$STOP_STDOUT"

assert_equal "$recording" "$(sed -n '1p' "$STOP_STDOUT")" \
  "stop output was not forwarded"
wait_for_file "$OMACUT_LOG"

[[ ! -e $ORDERING_ERROR ]] || fail "Omacut opened before recording finalization"
mapfile -d '' -t omacut_args <"$OMACUT_LOG"
assert_equal "1" "${omacut_args[0]:-}" "Omacut did not receive exactly one argument"
assert_equal "$recording" "${omacut_args[1]:-}" "Omacut received the wrong recording path"
[[ ! -e $INJECTION_SENTINEL ]] || fail "recording path was evaluated as shell code"
assert_equal "$recording" \
  "$(jq -r '.lastRecording' "$STATE_ROOT/omasnap/state.json")" \
  "completed recording was not saved in Omasnap state"

rm -f "$OMACUT_LOG"
rm -f "$STOP_COMPLETE"
printf '%s\n' "$recording" >"$RECORDING_MARKER"
if OMASNAP_TEST_FINALIZE_FILE="$recording" OMASNAP_TEST_STOP_OUTPUT="$recording" \
  OMASNAP_TEST_STOP_STATUS=7 run_omasnap >/dev/null; then
  fail "failed stop returned success"
else
  assert_equal "7" "$?" "failed stop status was not preserved"
fi
[[ ! -e $OMACUT_LOG ]] || fail "Omacut opened after a failed stop"

printf '%s\n' "$recording" >"$RECORDING_MARKER"
OMASNAP_TEST_FINALIZE_FILE="$recording" OMASNAP_TEST_STOP_OUTPUT="" \
  run_omasnap >/dev/null
[[ ! -e $OMACUT_LOG ]] || fail "Omacut opened without finalized-path output"

missing_recording="$TEST_ROOT/missing recording.mp4"
printf '%s\n' "$missing_recording" >"$RECORDING_MARKER"
OMASNAP_TEST_STOP_OUTPUT="$missing_recording" run_omasnap >/dev/null
[[ ! -e $OMACUT_LOG ]] || fail "Omacut opened a missing recording"

printf 'PASS: completed recording handoff\n'
