#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
STUB_BIN="$TEST_ROOT/bin"
DESTINATION_LOG="$TEST_ROOT/destination"
TEST_HOME="$TEST_ROOT/home"
VIDEOS_DIR="$TEST_ROOT/Videos"
DESKTOP_DIR="$TEST_ROOT/Desktop"

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

mkdir -p "$STUB_BIN" "$TEST_HOME"

cat >"$STUB_BIN/omarchy-capture-screenrecording" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$OMARCHY_SCREENRECORD_DIR" >"$OMASNAP_TEST_DESTINATION_LOG"
STUB

chmod +x "$STUB_BIN/omarchy-capture-screenrecording"

run_recording() {
  env \
    -u OMASNAP_RECORDING_DIR \
    -u OMARCHY_SCREENRECORD_DIR \
    PATH="$STUB_BIN:$PATH" \
    HOME="$TEST_HOME" \
    XDG_VIDEOS_DIR="$VIDEOS_DIR" \
    XDG_DESKTOP_DIR="$DESKTOP_DIR" \
    OMASNAP_TEST_DESTINATION_LOG="$DESTINATION_LOG" \
    "$PLUGIN_DIR/omasnap" record screen --settle=0 "$@"
}

run_recording --save-location=pictures
assert_equal "$VIDEOS_DIR" "$(<"$DESTINATION_LOG")" \
  "the recording-mode Pictures entry did not resolve to Videos"

run_recording --save-location=videos
assert_equal "$VIDEOS_DIR" "$(<"$DESTINATION_LOG")" \
  "the Videos destination did not resolve to the XDG Videos directory"

run_recording --save-location=desktop
assert_equal "$DESKTOP_DIR" "$(<"$DESTINATION_LOG")" \
  "the recording destination ignored Desktop"

printf 'PASS: recording destinations\n'
