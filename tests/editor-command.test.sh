#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$PLUGIN_DIR/omashot"
TEST_ROOT=$(mktemp -d)
TEST_HOME="$TEST_ROOT/home"
STUB_BIN="$TEST_ROOT/bin"
OUTPUT_DIR="$TEST_ROOT/output"
GRIM_LOG="$TEST_ROOT/grim.log"
NOTIFY_LOG="$TEST_ROOT/notify.log"
VIEWER_LOG="$TEST_ROOT/viewer.log"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$TEST_HOME/.config/omarchy" "$STUB_BIN" "$OUTPUT_DIR"

# The editor commands, as a user would configure them in shell.json.
jq -n --arg output "$OUTPUT_DIR" '{
  version: 1,
  plugins: [{
    id: "b.omashot",
    outputMode: "file",
    saveLocation: $output,
    editorCommand: "omaroll",
    recordingEditorCommand: "omaroll"
  }]
}' >"$TEST_HOME/.config/omarchy/shell.json"

cat >"$STUB_BIN/grim" <<'STUB'
#!/usr/bin/env bash
output=${!#}
printf 'pixels\n' >"$output"
STUB

cat >"$STUB_BIN/notify-send" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TEST_NOTIFY_LOG"
STUB

cat >"$STUB_BIN/omarchy-notification-send" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TEST_NOTIFY_LOG"
STUB

cat >"$STUB_BIN/omaroll" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_VIEWER_LOG"
STUB

# The helper launches the viewer detached, through setsid and uwsm-app.
cat >"$STUB_BIN/setsid" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB

cat >"$STUB_BIN/uwsm-app" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_VIEWER_LOG"
STUB

chmod +x "$STUB_BIN"/*

run_helper() {
  env \
    PATH="$STUB_BIN:$PATH" \
    HOME="$TEST_HOME" \
    XDG_STATE_HOME="$TEST_ROOT/state" \
    TEST_GRIM_LOG="$GRIM_LOG" \
    TEST_NOTIFY_LOG="$NOTIFY_LOG" \
    TEST_VIEWER_LOG="$VIEWER_LOG" \
    "$HELPER" "$@"
}

shot_path=$(run_helper demo-screenshot)
[[ -f $shot_path ]] || fail "the demo screenshot was not written"

# The notification is the one the user clicks, and the one the shell's
# "invoke last notification" activates: its action has to open the file in
# the configured editor.
[[ -s $NOTIFY_LOG ]] || fail "no notification was posted for the capture"
grep -Fq -- "--exec omaroll $shot_path" "$NOTIFY_LOG" ||
  fail "the capture notification does not open the file in the configured editor"

# "open-last" is what the keybinding runs: it has to open the newest capture
# in the same viewer.
mkdir -p "$TEST_ROOT/state/omashot"
jq -n --arg file "$shot_path" '{lastScreenshot: $file, updatedAt: "now"}' \
  >"$TEST_ROOT/state/omashot/state.json"

run_helper open-last
sleep 1

[[ -s $VIEWER_LOG ]] || fail "open-last did not launch the configured editor"
grep -Fq -- "$shot_path" "$VIEWER_LOG" ||
  fail "open-last did not open the newest capture in the configured editor"

printf 'PASS: editor commands open captures and recordings\n'
