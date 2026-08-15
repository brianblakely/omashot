#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
STUB_BIN="$TEST_ROOT/bin"
STATE_ROOT="$TEST_ROOT/state"
RECORDING_MARKER="$TEST_ROOT/recording-active"
HYPRCTL_LOG="$TEST_ROOT/hyprctl.log"
TEST_HOME="$TEST_ROOT/home"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_omashot() {
  env \
    PATH="$STUB_BIN:$PATH" \
    HOME="$TEST_HOME" \
    XDG_STATE_HOME="$STATE_ROOT" \
    TEST_RECORDING_MARKER="$RECORDING_MARKER" \
    TEST_HYPRCTL_LOG="$HYPRCTL_LOG" \
    "$PLUGIN_DIR/omashot" "$@"
}

mkdir -p "$STUB_BIN" "$TEST_HOME/.config/omarchy"

jq -n '{version: 1, plugins: [{id: "b.omashot"}]}' \
  >"$TEST_HOME/.config/omarchy/shell.json"

cat >"$STUB_BIN/omarchy-capture-screenrecording" <<'STUB'
#!/usr/bin/env bash
if [[ ${1:-} == --stop-recording ]]; then
  rm -f -- "$TEST_RECORDING_MARKER"
else
  : >"$TEST_RECORDING_MARKER"
fi
STUB

cat >"$STUB_BIN/pgrep" <<'STUB'
#!/usr/bin/env bash
[[ -e $TEST_RECORDING_MARKER ]]
STUB

cat >"$STUB_BIN/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_HYPRCTL_LOG"
STUB

cat >"$STUB_BIN/cat" <<'STUB'
#!/usr/bin/env bash
if [[ $# == 1 && $1 == /tmp/omarchy-screenrecord-filename ]]; then
  exit 1
fi
exec /usr/bin/cat "$@"
STUB

chmod +x "$STUB_BIN"/*

run_omashot record screen

grep -Fq 'hl.bind("ESCAPE"' "$HYPRCTL_LOG" ||
  fail "starting a recording did not bind Escape"
grep -Fq 'omarchy-shell b.omashot stopRecording' "$HYPRCTL_LOG" ||
  fail "Escape was not bound to the Omashot stop action"
[[ -e $STATE_ROOT/omashot/recording-escape-bound ]] ||
  fail "the active Escape binding was not tracked"

run_omashot stop-recording

grep -Fq 'omashot_recording_escape_bind:unbind()' "$HYPRCTL_LOG" ||
  fail "stopping a recording did not remove the Escape binding"
[[ ! -e $STATE_ROOT/omashot/recording-escape-bound ]] ||
  fail "the Escape binding marker remained after stopping"

run_omashot record screen
rm -f -- "$RECORDING_MARKER"
run_omashot status >/dev/null
[[ ! -e $STATE_ROOT/omashot/recording-escape-bound ]] ||
  fail "status refresh did not clean up Escape after an unexpected recording exit"

printf 'PASS: recording Escape binding\n'
