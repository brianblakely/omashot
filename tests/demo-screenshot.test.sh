#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OVERLAY="$PLUGIN_DIR/Overlay.qml"
SERVICE="$PLUGIN_DIR/Service.qml"
HELPER="$PLUGIN_DIR/omashot"
TEST_ROOT=$(mktemp -d)
TEST_HOME="$TEST_ROOT/home"
STUB_BIN="$TEST_ROOT/bin"
OUTPUT_DIR="$TEST_ROOT/output"
GRIM_LOG="$TEST_ROOT/grim.log"
SLEEP_LOG="$TEST_ROOT/sleep.log"
NOTIFY_LOG="$TEST_ROOT/notify.log"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local needle="$1" file="$2" message="$3"
  rg --fixed-strings --quiet -- "$needle" "$file" || fail "$message"
}

assert_contains 'property bool demoCaptureHeld: false' "$OVERLAY" \
  "the overlay does not track the held demo-capture key"
assert_contains 'event.key === Qt.Key_AsciiTilde' "$OVERLAY" \
  "the tilde key does not activate demo capture"
assert_contains 'event.key === Qt.Key_QuoteLeft && (event.modifiers & Qt.ShiftModifier) !== 0' "$OVERLAY" \
  "Shift+backtick does not activate demo capture"
assert_contains 'freezePidForScreenshot(), demoCaptureHeld' "$OVERLAY" \
  "screenshot requests do not carry the held demo-capture state"
assert_contains 'service.recordGeometry(geometry, targetScreen, demoCaptureHeld)' "$OVERLAY" \
  "region recording requests do not carry the held demo-capture state"
assert_contains 'service.record("screen", demoCaptureHeld, screenName, targetGeometry)' "$OVERLAY" \
  "screen recording requests do not carry the held demo-capture state"
assert_contains 'sequence: "Shift+Space"' "$OVERLAY" \
  "holding tilde prevents the Space capture shortcut"
assert_contains 'demoScreenshotProc.command = ["bash", helperPath, "demo-screenshot"]' "$SERVICE" \
  "the service does not capture the visible overlay first"
assert_contains 'function recordGeometry(geometry, screenName, includeDemo)' "$SERVICE" \
  "region recordings do not accept the demo-capture request"

record_geometry=$(sed -n '/^  function recordGeometry(geometry, screenName, includeDemo)/,/^  }/p' "$SERVICE")
rg --fixed-strings --quiet -- 'runCapture(["record", "selection"' <<<"$record_geometry" ||
  fail "region recordings do not run after the demo screenshot"
rg --fixed-strings --quiet -- '], includeDemo, true)' <<<"$record_geometry" ||
  fail "region recordings ignore the demo-capture request"

demo_exit=$(sed -n '/id: demoScreenshotProc/,/^  }/p' "$SERVICE")
rg --fixed-strings --quiet -- 'root.launchCapture(args, keepOverlay)' <<<"$demo_exit" ||
  fail "the requested capture is not sequenced after the demo screenshot"

launch_capture=$(sed -n '/^  function launchCapture(args, keepOverlay)/,/^  }/p' "$SERVICE")
hide_line=$(rg -n --fixed-strings 'else hide()' <<<"$launch_capture" | cut -d: -f1)
capture_line=$(rg -n --fixed-strings 'return runDetached(args)' <<<"$launch_capture" | cut -d: -f1)
[[ -n $hide_line && -n $capture_line && $hide_line -lt $capture_line ]] ||
  fail "ordinary captures do not hide the overlay before continuing"

mkdir -p "$TEST_HOME/.config/omarchy" "$STUB_BIN" "$OUTPUT_DIR"

jq -n --arg output "$OUTPUT_DIR" '{
  version: 1,
  plugins: [{
    id: "b.omashot",
    outputMode: "clipboard",
    saveLocation: $output,
    timerSeconds: 10,
    includeCursor: true
  }]
}' >"$TEST_HOME/.config/omarchy/shell.json"

cat >"$STUB_BIN/grim" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TEST_GRIM_LOG"
output=${!#}
printf 'demo pixels\n' >"$output"
STUB

cat >"$STUB_BIN/sleep" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$TEST_SLEEP_LOG"
STUB

cat >"$STUB_BIN/notify-send" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TEST_NOTIFY_LOG"
STUB

chmod +x "$STUB_BIN"/*

demo_path=$(env \
  PATH="$STUB_BIN:$PATH" \
  HOME="$TEST_HOME" \
  XDG_STATE_HOME="$TEST_ROOT/state" \
  TEST_GRIM_LOG="$GRIM_LOG" \
  TEST_SLEEP_LOG="$SLEEP_LOG" \
  TEST_NOTIFY_LOG="$NOTIFY_LOG" \
  "$HELPER" demo-screenshot)

[[ -f $demo_path ]] || fail "the demo screenshot was not written"
[[ $demo_path == "$OUTPUT_DIR"/omashot-demo-*.png ]] ||
  fail "the demo screenshot used the wrong destination or filename"
if rg -q '(^|[[:space:]])-g([[:space:]]|$)' "$GRIM_LOG"; then
  fail "the demo screenshot was limited to a region"
fi
grep -Eq '(^|[[:space:]])-c([[:space:]]|$)' "$GRIM_LOG" ||
  fail "the demo screenshot ignored the configured cursor setting"
[[ ! -e $SLEEP_LOG ]] || fail "the demo screenshot applied the normal capture timer"
grep -Fq 'Omashot demo screenshot saved' "$NOTIFY_LOG" ||
  fail "the demo screenshot did not identify its saved file"

printf 'PASS: held-tilde demo screenshot\n'
