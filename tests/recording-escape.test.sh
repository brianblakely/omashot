#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
STUB_BIN="$TEST_ROOT/bin"
STATE_ROOT="$TEST_ROOT/state"
RECORDING_MARKER="$TEST_ROOT/recording-active"
HYPRCTL_LOG="$TEST_ROOT/hyprctl.log"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_omasnap() {
  env \
    PATH="$STUB_BIN:$PATH" \
    XDG_STATE_HOME="$STATE_ROOT" \
    OMASNAP_TEST_RECORDING_MARKER="$RECORDING_MARKER" \
    OMASNAP_TEST_HYPRCTL_LOG="$HYPRCTL_LOG" \
    "$PLUGIN_DIR/omasnap" "$@"
}

mkdir -p "$STUB_BIN"

cat >"$STUB_BIN/omarchy-capture-screenrecording" <<'STUB'
#!/usr/bin/env bash
if [[ ${1:-} == --stop-recording ]]; then
  rm -f -- "$OMASNAP_TEST_RECORDING_MARKER"
else
  : >"$OMASNAP_TEST_RECORDING_MARKER"
fi
STUB

cat >"$STUB_BIN/pgrep" <<'STUB'
#!/usr/bin/env bash
[[ -e $OMASNAP_TEST_RECORDING_MARKER ]]
STUB

cat >"$STUB_BIN/hyprctl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OMASNAP_TEST_HYPRCTL_LOG"
STUB

cat >"$STUB_BIN/cat" <<'STUB'
#!/usr/bin/env bash
if [[ $# == 1 && $1 == /tmp/omarchy-screenrecord-filename ]]; then
  exit 1
fi
exec /usr/bin/cat "$@"
STUB

chmod +x "$STUB_BIN"/*

run_omasnap record screen --settle=0

grep -Fq 'hl.bind("ESCAPE"' "$HYPRCTL_LOG" ||
  fail "starting a recording did not bind Escape"
grep -Fq 'omarchy-shell b.omashot stopRecording' "$HYPRCTL_LOG" ||
  fail "Escape was not bound to the Omashot stop action"
[[ -e $STATE_ROOT/omasnap/recording-escape-bound ]] ||
  fail "the active Escape binding was not tracked"

run_omasnap stop-recording

grep -Fq 'omasnap_recording_escape_bind:unbind()' "$HYPRCTL_LOG" ||
  fail "stopping a recording did not remove the Escape binding"
[[ ! -e $STATE_ROOT/omasnap/recording-escape-bound ]] ||
  fail "the Escape binding marker remained after stopping"

run_omasnap record screen --settle=0
rm -f -- "$RECORDING_MARKER"
run_omasnap status >/dev/null
[[ ! -e $STATE_ROOT/omasnap/recording-escape-bound ]] ||
  fail "status refresh did not clean up Escape after an unexpected recording exit"

printf 'PASS: recording Escape binding\n'
