#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$PLUGIN_DIR/omashot"
SERVICE="$PLUGIN_DIR/Service.qml"
TEST_ROOT=$(mktemp -d)
TEST_HOME="$TEST_ROOT/home"
STUB_BIN="$TEST_ROOT/bin"
OUTPUT_DIR="$TEST_ROOT/output"
GRIM_LOG="$TEST_ROOT/grim.log"
SLEEP_LOG="$TEST_ROOT/sleep.log"
EDITOR_LOG="$TEST_ROOT/editor.log"
RECORDING_ARGS_LOG="$TEST_ROOT/recording-args.log"
RECORDING_DIR_LOG="$TEST_ROOT/recording-dir.log"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_source_absent() {
  local needle="$1" file="$2" message="$3"
  if rg --fixed-strings --quiet -- "$needle" "$file"; then
    fail "$message"
  fi
}

for option in --output-mode --save-location --timer --cursor --settle --editor; do
  assert_source_absent "$option" "$HELPER" "the helper still accepts $option configuration"
  assert_source_absent "$option" "$SERVICE" "the service still passes $option configuration"
done

legacy_prefix="OMA""SHOT_"
assert_source_absent "$legacy_prefix" "$HELPER" \
  "the helper still reads legacy Omashot environment configuration"
rg --fixed-strings --quiet -- 'SHELL_CONFIG_FILE="$HOME/.config/omarchy/shell.json"' "$HELPER" ||
  fail "the helper does not read Omarchy shell configuration"
rg --fixed-strings --quiet -- 'first(.plugins[]? | select(.id == $id)) // {}' "$HELPER" ||
  fail "the helper does not select its b.omashot plugin entry"

mkdir -p "$TEST_HOME/.config/omarchy" "$STUB_BIN" "$OUTPUT_DIR"

jq -n --arg output "$OUTPUT_DIR" '{
  version: 1,
  plugins: [{
    id: "b.omashot",
    outputMode: "editor",
    saveLocation: $output,
    timerSeconds: 5,
    includeCursor: true,
    editorCommand: "test-screenshot-editor"
  }]
}' >"$TEST_HOME/.config/omarchy/shell.json"

if env HOME="$TEST_HOME" "$HELPER" screenshot --output-mode=file >/dev/null 2>&1; then
  fail "a retired command-line configuration option was accepted"
fi

cat >"$STUB_BIN/grim" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TEST_GRIM_LOG"
output=${!#}
printf 'pixels\n' >"$output"
STUB

cat >"$STUB_BIN/sleep" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$TEST_SLEEP_LOG"
STUB

cat >"$STUB_BIN/test-screenshot-editor" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$TEST_EDITOR_LOG"
STUB

cat >"$STUB_BIN/notify-send" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

cat >"$STUB_BIN/omarchy-capture-screenrecording" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TEST_RECORDING_ARGS_LOG"
printf '%s\n' "$OMARCHY_SCREENRECORD_DIR" >"$TEST_RECORDING_DIR_LOG"
STUB

cat >"$STUB_BIN/pgrep" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB

chmod +x "$STUB_BIN"/*

env \
  PATH="$STUB_BIN:$PATH" \
  HOME="$TEST_HOME" \
  XDG_STATE_HOME="$TEST_ROOT/state" \
  TEST_GRIM_LOG="$GRIM_LOG" \
  TEST_SLEEP_LOG="$SLEEP_LOG" \
  TEST_EDITOR_LOG="$EDITOR_LOG" \
  "$HELPER" screenshot screen >/dev/null

for ((attempt = 0; attempt < 40; attempt++)); do
  [[ -f $EDITOR_LOG ]] && break
  sleep 0.05
done

[[ -f $EDITOR_LOG ]] || fail "the shell.json editor command was not launched"
grep -Eq '(^|[[:space:]])-c([[:space:]]|$)' "$GRIM_LOG" ||
  fail "the shell.json cursor setting was ignored"
grep -Fxq '5' "$SLEEP_LOG" || fail "the shell.json timer setting was ignored"
[[ $(<"$EDITOR_LOG") == "$OUTPUT_DIR"/* ]] ||
  fail "the shell.json save location was ignored"

jq -n --arg output "$OUTPUT_DIR" '{
  version: 1,
  plugins: [{
    id: "b.omashot",
    saveLocation: $output,
    recordDesktopAudio: true,
    recordMicrophoneAudio: true,
    recordWebcam: true
  }]
}' >"$TEST_HOME/.config/omarchy/shell.json"

env \
  PATH="$STUB_BIN:$PATH" \
  HOME="$TEST_HOME" \
  XDG_STATE_HOME="$TEST_ROOT/state" \
  TEST_RECORDING_ARGS_LOG="$RECORDING_ARGS_LOG" \
  TEST_RECORDING_DIR_LOG="$RECORDING_DIR_LOG" \
  TEST_SLEEP_LOG="$SLEEP_LOG" \
  "$HELPER" record screen

grep -Fq -- '--with-desktop-audio' "$RECORDING_ARGS_LOG" ||
  fail "the shell.json desktop-audio setting was ignored"
grep -Fq -- '--with-microphone-audio' "$RECORDING_ARGS_LOG" ||
  fail "the shell.json microphone setting was ignored"
grep -Fq -- '--with-webcam' "$RECORDING_ARGS_LOG" ||
  fail "the shell.json webcam setting was ignored"
[[ $(<"$RECORDING_DIR_LOG") == "$OUTPUT_DIR" ]] ||
  fail "the shell.json recording location was ignored"

printf 'PASS: shell.json is the Omashot configuration source\n'
