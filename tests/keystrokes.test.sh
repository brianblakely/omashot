#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SERVICE="$PLUGIN_DIR/Service.qml"
OVERLAY="$PLUGIN_DIR/Overlay.qml"
KEYSTROKE_OVERLAY="$PLUGIN_DIR/KeystrokeOverlay.qml"
HELPER="$PLUGIN_DIR/omashot"
TEST_ROOT=$(mktemp -d)
TEST_HOME="$TEST_ROOT/home"
STATE_ROOT="$TEST_ROOT/state"
STUB_BIN="$TEST_ROOT/bin"
RECORDING_MARKER="$TEST_ROOT/recording-active"
LOCK_MARKER="$TEST_ROOT/session-locked"
FAIL_START_MARKER="$TEST_ROOT/fail-start"
HYPRCTL_LOG="$TEST_ROOT/hyprctl.log"
RECORDER_LOG="$TEST_ROOT/recorder.log"

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

assert_absent() {
  local needle="$1" file="$2" message="$3"
  if rg --fixed-strings --quiet -- "$needle" "$file"; then
    fail "$message"
  fi
}

assert_equal() {
  local expected="$1" actual="$2" message="$3"
  [[ $actual == "$expected" ]] ||
    fail "$message (expected '$expected', got '$actual')"
}

run_omashot() {
  env \
    PATH="$STUB_BIN:$PATH" \
    HOME="$TEST_HOME" \
    XDG_STATE_HOME="$STATE_ROOT" \
    TEST_RECORDING_MARKER="$RECORDING_MARKER" \
    TEST_LOCK_MARKER="$LOCK_MARKER" \
    TEST_FAIL_START_MARKER="$FAIL_START_MARKER" \
    TEST_HYPRCTL_LOG="$HYPRCTL_LOG" \
    TEST_RECORDER_LOG="$RECORDER_LOG" \
    "$HELPER" "$@"
}

write_settings() {
  local enabled="$1"
  jq -n --argjson enabled "$enabled" '{
    version: 1,
    plugins: [{id: "b.omashot", recordKeystrokes: $enabled}]
  }' >"$TEST_HOME/.config/omarchy/shell.json"
}

# Public state and UI surface.
assert_contains 'readonly property bool recordKeystrokes: setting("recordKeystrokes", false) === true' \
  "$SERVICE" "recordKeystrokes does not default to off"
assert_contains 'recordKeystrokes: recordKeystrokes,' "$SERVICE" \
  "service status omits recordKeystrokes"
assert_contains 'function setRecordKeystrokes(value)' "$SERVICE" \
  "the persisted keystroke setter is missing"
assert_contains 'saveSettings({ recordKeystrokes: next })' "$SERVICE" \
  "the keystroke setter is not persisted"
assert_contains 'function keystrokes(value: string): string' "$SERVICE" \
  "the keystrokes IPC method is missing"
assert_contains 'tooltipText: "Keystrokes: "' "$OVERLAY" \
  "the recording toolbar keystroke toggle is missing"
assert_contains 'onClicked: root.toggleBoolean("keystrokes")' "$OVERLAY" \
  "the recording toolbar toggle is not wired to the service"
assert_contains 'service.record("screen", demoCaptureHeld, screenName, targetGeometry)' \
  "$OVERLAY" "screen recording bounds are not passed to the service"

# The QML endpoints and Lua binding catalog must remain in lockstep.
sed -n '/readonly property var keystrokeCatalog:/,/^  ]/p' "$SERVICE" \
  | rg -o 'shortcut: "[^"]+' | sed 's/shortcut: "//' | sort >"$TEST_ROOT/qml-shortcuts"
{
  sed -n '/^local ordinary = {$/,/^}$/p' "$HELPER"
  sed -n '/^local modifiers = {$/,/^}$/p' "$HELPER"
  printf '%s\n' '"key-escape"'
} | rg -o '"(key|modifier)-[^"]+"' | tr -d '"' | sort >"$TEST_ROOT/lua-shortcuts"

assert_equal "103" "$(wc -l <"$TEST_ROOT/qml-shortcuts" | tr -d ' ')" \
  "the supported Quickshell key catalog changed unexpectedly"
assert_equal "103" "$(sort -u "$TEST_ROOT/qml-shortcuts" | wc -l | tr -d ' ')" \
  "the Quickshell key catalog contains duplicate shortcut names"
if ! cmp -s "$TEST_ROOT/qml-shortcuts" "$TEST_ROOT/lua-shortcuts"; then
  diff -u "$TEST_ROOT/qml-shortcuts" "$TEST_ROOT/lua-shortcuts" >&2 || true
  fail "the Hyprland and Quickshell shortcut catalogs differ"
fi

for shortcut in key-a key-slash key-page-up key-left key-f12 key-kp-enter \
  modifier-ctrl-left modifier-shift-right key-escape; do
  rg --fixed-strings --quiet -- "$shortcut" "$TEST_ROOT/qml-shortcuts" ||
    fail "supported shortcut $shortcut is missing"
done

assert_absent '"CTRL + CONTROL_L"' "$HELPER" \
  "left Ctrl still uses a self-modifier chord that can lose its release"
assert_absent '"SHIFT + SHIFT_L"' "$HELPER" \
  "left Shift still uses a self-modifier chord that can lose its release"
for modifier_key in Control_L Control_R Shift_L Shift_R Alt_L Alt_R Super_L Super_R; do
  assert_contains "{ \"$modifier_key\", \"modifier-" "$HELPER" \
    "$modifier_key is not bound without a redundant modifier chord"
done
assert_contains 'onReleased: root.keystrokeReleased(keystrokeShortcutDelegate.modelData)' \
  "$SERVICE" "global shortcut releases are not routed to the keystroke service"

global_binding_helper=$(sed -n '/^local function add_global_binding/,/^end$/p' "$HELPER")
for option in 'non_consuming = true' 'ignore_mods = true' 'repeating = true' \
  'locked = false' 'dont_inhibit = false' 'allow_input_capture = false'; do
  rg --fixed-strings --quiet -- "$option" <<<"$global_binding_helper" ||
    fail "ordinary recording bindings omit $option"
done
assert_contains 'release = true' "$HELPER" \
  "recording shortcuts have no explicit release binding"
assert_equal "2" \
  "$(rg -c 'table\.insert\(bindings, hl\.bind' <<<"$global_binding_helper")" \
  "recording shortcuts are not created as press/release pairs"
assert_contains 'expected_binding_count = (#ordinary + #modifiers + 1) * 2' "$HELPER" \
  "the cached binding set does not validate every press/release pair"
assert_contains 'add_global_binding(bindings, entry, "Track modifier in Omashot recording", false, true)' \
  "$HELPER" "modifier shortcuts are not paired with release bindings"
assert_contains 'add_global_binding(bindings, { "ESCAPE", "key-escape" },' "$HELPER" \
  "Escape is not paired with a release binding"
assert_contains 'tracker.subscription = hl.on("input.keyboard.key", function()' "$HELPER" \
  "physical modifier changes are not observed"
assert_contains 'local pressed = hl.is_key_down(entry[1])' "$HELPER" \
  "modifier state is not reconciled with Hyprland's pressed-key set"
assert_contains 'tracker.timer = hl.timer(reconcile_modifiers, { timeout = 1, type = "repeat" })' \
  "$HELPER" "modifier reconciliation does not wait for Hyprland's key state update"
assert_contains 'hl.dsp.event("b.omashot-modifier," .. entry[2] .. ",0")' "$HELPER" \
  "physical modifier releases are not sent to Quickshell"
assert_equal "3" "$(rg -c 'if omashot_recording_modifier_tracker then' "$HELPER")" \
  "modifier tracking is not cleaned during every input-binding transition"
assert_contains 'omashot_recording_binding_sets = omashot_recording_binding_sets or {}' \
  "$HELPER" \
  "recording binding handles do not have a dedicated table"
assert_contains 'for _, binding in ipairs(bindings) do binding:set_enabled(false) end' \
  "$HELPER" "recording bindings are not disabled through their own handles"
assert_absent 'binding:unbind()' "$HELPER" \
  "recording cleanup uses Hyprland's broad Lua unbind operation"
assert_absent 'hl.unbind' "$HELPER" \
  "recording cleanup can remove unrelated user bindings"
assert_absent 'showmethekey' "$PLUGIN_DIR/README.md" \
  "documentation introduces an external keystroke dependency"
assert_absent 'showmethekey' "$HELPER" \
  "the helper introduces an external keystroke dependency"

# Sequence behavior, modifier composition, Escape handling, and rendering.
assert_contains 'if (lastKeystrokeAt <= 0 || now - lastKeystrokeAt > 500) entries = []' \
  "$SERVICE" "keystroke sequences do not roll over after 500ms"
assert_contains 'Math.max(1, Number(last.count) || 1) + 1' "$SERVICE" \
  "held-key repeats are not collapsed into a count"
assert_contains 'keystrokeEntries = keystrokeEntries.slice(1)' "$SERVICE" \
  "over-wide sequences do not remove their oldest entry"
assert_contains 'if (active.ctrl) labels.push("Ctrl")' "$SERVICE" \
  "Ctrl is not composed into shortcut labels"
assert_contains 'if (active.shift) labels.push("Shift")' "$SERVICE" \
  "Shift is not composed into shortcut labels"
assert_contains 'var chord = activeModifierDisplays()' "$SERVICE" \
  "modifier chords are not rendered with their configured icon fonts"
assert_contains 'appendKeystroke(entry.glyph || entry.label, wasPressed, entry.fontFamily)' "$SERVICE" \
  "non-character keys do not prefer their Nerd Font glyphs"
assert_contains 'glyph: "\ue900", fontFamily: "omarchy"' "$SERVICE" \
  "Super does not use the Omarchy U+E900 icon"
assert_contains 'textFormat: Text.RichText' "$KEYSTROKE_OVERLAY" \
  "the keystroke row cannot render a font-specific Super glyph"
assert_contains 'font-family:' "$SERVICE" \
  "keystroke chords do not retain per-glyph font families"
assert_contains 'function setPhysicalModifierState(shortcut, pressed)' "$SERVICE" \
  "physical modifier state updates are not handled"
assert_contains 'if (pressed === alreadyPressed) return' "$SERVICE" \
  "duplicate modifier state updates are not idempotent"
assert_contains 'fields[0] !== "b.omashot-modifier"' "$SERVICE" \
  "Hyprland modifier events are not namespaced"
assert_contains 'function onRawEvent(event) { root.handleHyprlandEvent(event) }' "$SERVICE" \
  "Hyprland modifier events are not routed to the service"

catalog_entry() {
  rg --fixed-strings -- "{ shortcut: \"$1\"," "$SERVICE"
}

assert_catalog_glyph() {
  local shortcut="$1" glyph="$2" entry
  entry=$(catalog_entry "$shortcut")
  [[ $entry == *"glyph: \"$glyph\""* ]] ||
    fail "$shortcut does not use the expected configured glyph"
}

while read -r shortcut glyph; do
  assert_catalog_glyph "$shortcut" "$glyph"
done <<'GLYPHS'
key-space 󱁐
key-tab 󰌒
key-enter 󰌑
key-backspace 󰌍
key-insert 
key-delete 󰆴
key-home 󰋜
key-end 󰘁
key-page-up 󰞕
key-page-down 󰞒
key-left 󰁍
key-right 󰁔
key-up 󰁝
key-down 󰁅
key-caps-lock 󰘲
key-num-lock 󰎠
key-print 󰐪
key-pause 󰏤
key-f1 󱊫
key-f2 󱊬
key-f3 󱊭
key-f4 󱊮
key-f5 󱊯
key-f6 󱊰
key-f7 󱊱
key-f8 󱊲
key-f9 󱊳
key-f10 󱊴
key-f11 󱊵
key-f12 󱊶
key-kp-enter 󰌑
key-escape 󱊷
modifier-ctrl-left 󰘴
modifier-ctrl-right 󰘴
modifier-shift-left 󰘶
modifier-shift-right 󰘶
modifier-alt-left 󰘵
modifier-alt-right 󰘵
modifier-super-left \ue900
modifier-super-right \ue900
GLYPHS

for shortcut in key-a key-0 key-slash key-kp-0 key-kp-add; do
  [[ $(catalog_entry "$shortcut") != *'glyph:'* ]] ||
    fail "$shortcut should remain a printable character label"
done

assert_contains '{ shortcut: "key-page-up", label: "Page Up", glyph: "󰞕" }' \
  "$SERVICE" "human-readable special-key labels are missing"
assert_contains 'id: keystrokeClearTimer' "$SERVICE" \
  "the keystroke clear timer is missing"
assert_contains 'interval: 2000' "$SERVICE" \
  "the key row or Escape hold does not use the required two-second interval"
assert_contains 'onTriggered: root.keystrokeEntries = []' "$SERVICE" \
  "the recent sequence is not cleared abruptly"
assert_contains 'escapeHoldTimer.restart()' "$SERVICE" \
  "Escape press does not start the hold timer"
assert_contains 'escapeHoldTimer.stop()' "$SERVICE" \
  "Escape release does not cancel the hold timer"
assert_contains 'runDetached(["pass-escape"' "$SERVICE" \
  "short Escape presses are not forwarded to the active application"
assert_contains 'if (recording && service && service.recordKeystrokes) return' "$OVERLAY" \
  "enabled recordings still use the immediate overlay Escape path"
assert_contains 'Component.onDestruction: root.runDetached(["cleanup-recording-input"])' \
  "$SERVICE" "service teardown does not clean temporary bindings"

assert_contains 'mask: Region {}' "$KEYSTROKE_OVERLAY" \
  "the keystroke overlay is not click-through"
assert_contains 'readonly property real edgeInset: panel.targetRect.width > 80 ? 40 : 0' \
  "$KEYSTROKE_OVERLAY" "the key row is not inset 40px from the target edge"
assert_contains 'panel.targetRect.y + panel.targetRect.height - 40 - height' \
  "$KEYSTROKE_OVERLAY" "the key row is not inset 40px from the target bottom"
assert_contains 'width: Math.min(availableWidth' "$KEYSTROKE_OVERLAY" \
  "the key row is not constrained to the recorded target width"
assert_contains 'height: Math.min(panel.targetRect.height' "$KEYSTROKE_OVERLAY" \
  "the key row is not constrained to the recorded target height"
assert_contains 'color: Color.foreground' "$KEYSTROKE_OVERLAY" \
  "the key row does not use the inverse theme background"
assert_contains 'color: Color.background' "$KEYSTROKE_OVERLAY" \
  "the key row does not use the inverse theme text color"
assert_contains 'font.pixelSize: Style.font.body * 3' "$KEYSTROKE_OVERLAY" \
  "the key row font is not three times the standard body size"
assert_absent 'Behavior on opacity' "$KEYSTROKE_OVERLAY" \
  "the key row fades instead of clearing abruptly"

mkdir -p "$TEST_HOME/.config/omarchy" "$STUB_BIN"

jq -n '{version: 1, plugins: [{id: "b.omashot"}]}' \
  >"$TEST_HOME/.config/omarchy/shell.json"

cat >"$STUB_BIN/omarchy-capture-screenrecording" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_RECORDER_LOG"
if [[ ${1:-} == --stop-recording ]]; then
  rm -f -- "$TEST_RECORDING_MARKER"
  exit 0
fi
[[ ! -e $TEST_FAIL_START_MARKER ]] || exit 7
: >"$TEST_RECORDING_MARKER"
STUB

cat >"$STUB_BIN/pgrep" <<'STUB'
#!/usr/bin/env bash
[[ -e $TEST_RECORDING_MARKER ]]
STUB

cat >"$STUB_BIN/omarchy-hyprland-session-locked" <<'STUB'
#!/usr/bin/env bash
[[ -e $TEST_LOCK_MARKER ]]
STUB

cat >"$STUB_BIN/hyprctl" <<'STUB'
#!/usr/bin/env bash
if [[ ${1:-} == monitors && ${2:-} == -j ]]; then
  printf '%s\n' '[{"name":"DP-1","x":1920,"y":-100,"width":1920,"height":1080,"scale":1,"transform":0,"focused":true,"activeWorkspace":{"id":1},"solitaryBlockedBy":[]}]'
  exit 0
fi
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

default_status=$(run_omashot status)
assert_equal "false" "$(jq -r '.recordKeystrokes' <<<"$default_status")" \
  "recordKeystrokes is not off by default"

write_settings true
persisted_status=$(run_omashot status)
assert_equal "true" "$(jq -r '.recordKeystrokes' <<<"$persisted_status")" \
  "recordKeystrokes is not read from persisted plugin settings"

capture_context='{"screenName":"DP-1","targetGeometry":"0,0 1920x1080"}'
run_omashot record screen "$capture_context"
assert_equal "keystrokes" "$(<"$STATE_ROOT/omashot/recording-escape-bound")" \
  "an enabled recording did not install keystroke bindings"
assert_equal "1920,-100 1920x1080" \
  "$(jq -r '.geometry' "$STATE_ROOT/omashot/recording-context.json")" \
  "screen recording geometry was not converted to global coordinates"
assert_equal "DP-1" \
  "$(jq -r '.screenName' "$STATE_ROOT/omashot/recording-context.json")" \
  "screen recording monitor metadata was not retained"

for source_fragment in '"key-a"' '"key-page-up"' '"key-f12"' \
  '"modifier-ctrl-left"' '{ "ESCAPE", "key-escape" }' 'release = true'; do
  assert_contains "$source_fragment" "$HYPRCTL_LOG" \
    "the installed dynamic bindings omit $source_fragment"
done

recording_status=$(run_omashot status)
assert_equal "true" "$(jq -r '.recording' <<<"$recording_status")" \
  "an active recording is missing from status"
assert_equal "1920,-100 1920x1080" \
  "$(jq -r '.recordingGeometry' <<<"$recording_status")" \
  "recording bounds are missing from status"
assert_equal "DP-1" "$(jq -r '.recordingScreenName' <<<"$recording_status")" \
  "recording monitor is missing from status"

run_omashot sync-recording-input false
assert_equal "immediate" "$(<"$STATE_ROOT/omashot/recording-escape-bound")" \
  "disabling keystrokes during recording did not restore immediate Escape"
assert_contains 'omarchy-shell b.omashot stopRecording' "$HYPRCTL_LOG" \
  "the disabled state has no immediate Escape stop binding"

run_omashot sync-recording-input true
assert_equal "keystrokes" "$(<"$STATE_ROOT/omashot/recording-escape-bound")" \
  "enabling keystrokes during recording did not restore dynamic bindings"

run_omashot pass-escape "" '{"modifiers":"CTRL + SHIFT"}'
assert_contains 'state = "down", mods = "CTRL + SHIFT", key = "ESCAPE"' \
  "$HYPRCTL_LOG" "a short Escape tap does not synthesize key-down"
assert_contains 'state = "up", mods = "CTRL + SHIFT", key = "ESCAPE"' \
  "$HYPRCTL_LOG" "a short Escape tap does not synthesize key-up"
if run_omashot pass-escape "" '{"modifiers":"META"}'; then
  fail "pass-escape accepted an untrusted modifier expression"
fi

: >"$LOCK_MARKER"
run_omashot status >/dev/null
[[ ! -e $STATE_ROOT/omashot/recording-escape-bound ]] ||
  fail "recording bindings remained enabled on the lock screen"
rm -f -- "$LOCK_MARKER"
run_omashot status >/dev/null
assert_equal "keystrokes" "$(<"$STATE_ROOT/omashot/recording-escape-bound")" \
  "recording bindings were not restored after unlocking"

rm -f -- "$RECORDING_MARKER"
run_omashot status >/dev/null
[[ ! -e $STATE_ROOT/omashot/recording-escape-bound ]] ||
  fail "unexpected recorder exit left dynamic bindings behind"
[[ ! -e $STATE_ROOT/omashot/recording-context.json ]] ||
  fail "unexpected recorder exit left target metadata behind"

: >"$FAIL_START_MARKER"
if run_omashot record screen "$capture_context"; then
  fail "a failed recorder startup returned success"
else
  assert_equal "7" "$?" "a failed recorder startup lost its exit status"
fi
[[ ! -e $STATE_ROOT/omashot/recording-escape-bound ]] ||
  fail "failed recorder startup left dynamic bindings behind"
[[ ! -e $STATE_ROOT/omashot/recording-context.json ]] ||
  fail "failed recorder startup left target metadata behind"
rm -f -- "$FAIL_START_MARKER"

run_omashot record screen "$capture_context"
run_omashot stop-recording >/dev/null
[[ ! -e $STATE_ROOT/omashot/recording-escape-bound ]] ||
  fail "normal recording stop left dynamic bindings behind"
[[ ! -e $STATE_ROOT/omashot/recording-context.json ]] ||
  fail "normal recording stop left target metadata behind"

printf 'PASS: dependency-free recording keystrokes\n'
