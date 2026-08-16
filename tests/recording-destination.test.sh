#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
STUB_BIN="$TEST_ROOT/bin"
DESTINATION_LOG="$TEST_ROOT/destination"
SCREENSHOT_DESTINATION_LOG="$TEST_ROOT/screenshot-destination"
TEST_HOME="$TEST_ROOT/home"
STATE_ROOT="$TEST_ROOT/state"
VIDEOS_DIR="$TEST_ROOT/Videos"
PICTURES_DIR="$TEST_ROOT/Pictures"

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

mkdir -p "$STUB_BIN" "$TEST_HOME/.config/omarchy"

cat >"$STUB_BIN/omarchy-capture-screenrecording" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$OMARCHY_SCREENRECORD_DIR" >"$TEST_DESTINATION_LOG"
STUB

cat >"$STUB_BIN/grim" <<'STUB'
#!/usr/bin/env bash
output=${!#}
printf '%s\n' "$output" >"$TEST_SCREENSHOT_DESTINATION_LOG"
printf 'pixels\n' >"$output"
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

run_recording() {
  env \
    -u OMARCHY_SCREENRECORD_DIR \
    PATH="$STUB_BIN:$PATH" \
    HOME="$TEST_HOME" \
    XDG_STATE_HOME="$STATE_ROOT" \
    XDG_VIDEOS_DIR="$VIDEOS_DIR" \
    TEST_DESTINATION_LOG="$DESTINATION_LOG" \
    "$PLUGIN_DIR/omashot" record screen
}

run_screenshot() {
  env \
    PATH="$STUB_BIN:$PATH" \
    HOME="$TEST_HOME" \
    XDG_STATE_HOME="$STATE_ROOT" \
    XDG_PICTURES_DIR="$PICTURES_DIR" \
    TEST_SCREENSHOT_DESTINATION_LOG="$SCREENSHOT_DESTINATION_LOG" \
    "$PLUGIN_DIR/omashot" screenshot screen >/dev/null
}

write_settings() {
  local location="$1"
  jq -n --arg location "$location" '{
    version: 1,
    plugins: [{id: "b.omashot", outputMode: "file", saveLocation: $location}]
  }' >"$TEST_HOME/.config/omarchy/shell.json"
}

write_settings pictures
run_recording
assert_equal "$VIDEOS_DIR" "$(<"$DESTINATION_LOG")" \
  "the recording-mode Pictures entry did not resolve to Videos"

write_settings videos
run_recording
assert_equal "$VIDEOS_DIR" "$(<"$DESTINATION_LOG")" \
  "the Videos destination did not resolve to the XDG Videos directory"

write_settings desktop
run_screenshot
[[ $(<"$SCREENSHOT_DESTINATION_LOG") == "$PICTURES_DIR"/screenshot-*.png ]] ||
  fail "the retired Desktop destination did not fall back to Pictures"

run_recording
assert_equal "$VIDEOS_DIR" "$(<"$DESTINATION_LOG")" \
  "the retired Desktop destination did not fall back to Videos"

printf 'PASS: capture destinations\n'
