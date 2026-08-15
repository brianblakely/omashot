#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OVERLAY="$PLUGIN_DIR/Overlay.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local needle="$1" message="$2"
  rg --fixed-strings --quiet -- "$needle" "$OVERLAY" || fail "$message"
}

assert_absent() {
  local needle="$1" message="$2"
  if rg --fixed-strings --quiet -- "$needle" "$OVERLAY"; then
    fail "$message"
  fi
}

mode_options=$(sed -n '/readonly property var captureKinds:/,/^  ]/p' "$OVERLAY")
mode_count=$(rg --count '^\s*\{ value:' <<<"$mode_options")
[[ $mode_count == 2 ]] || fail "the toolbar does not expose exactly two capture modes"
rg --fixed-strings --quiet -- 'value: "screenshot", label: "Screenshot"' <<<"$mode_options" ||
  fail "the Screenshot mode is missing"
rg --fixed-strings --quiet -- 'value: "recording", label: "Recording"' <<<"$mode_options" ||
  fail "the Recording mode is missing or has the wrong label"
assert_contains 'id: captureKindButtons' "the capture mode button row is missing"
assert_contains 'height: captureKindButtons.height' \
  "capture mode buttons do not match the other toolbar controls"
assert_contains 'labelText: String(modelData.label || "")' \
  "capture modes are not using the toolbar button treatment"

assert_contains 'property string captureKind: "screenshot"' \
  "the overlay does not initialize in Screenshot mode"
assert_contains 'captureKind = "screenshot"' \
  "opening the normal overlay does not reset it to Screenshot mode"
assert_absent 'captureModes' "the legacy five-button mode model is still present"
assert_absent 'selectedMode' "capture type is still coupled to legacy target modes"

set_capture_kind_function=$(sed -n '/^  function setCaptureKind(kind)/,/^  }/p' "$OVERLAY")
rg --fixed-strings --quiet -- 'if (captureKind === nextKind) {' <<<"$set_capture_kind_function" ||
  fail "clicking the selected capture mode does not enter default mouse selection"
rg --fixed-strings --quiet -- 'clearSelection()' <<<"$set_capture_kind_function" ||
  fail "clicking the selected capture mode does not erase the active target"

assert_contains 'function updateTargetHover(' "window hover targeting is missing"
assert_contains 'var client = clientAt(' "hover targeting does not inspect the window under the pointer"
assert_contains 'if (isPointAtTopEdge(y))' "top-edge screen targeting is missing"
assert_contains 'root.beginTargetPointer(' "pointer presses do not use unified target selection"
assert_contains 'onReleased: root.finishTargetPointer(' "pointer clicks do not execute unified targets"
assert_contains 'pointerAction = "draw"' "pointer drags cannot create a region"
assert_contains 'targetKind = "region"' "dragged selections are not marked as regions"
assert_contains 'if (targetKind === "region" && hasSelection) {' \
  "hovering outside a region can still replace it with a screen or window target"
assert_contains 'if (regionOnlyPicker || (targetKind === "region" && hasSelection)) {' \
  "an existing region does not disable screen and window pointer targeting"
assert_contains 'if (action === "region-draw-pending" || action === "region-move-pending") {' \
  "clicking outside an existing region does not remain a region operation"
assert_contains 'root.captureSelectedTarget(panel.currentScreenName)' \
  "Enter does not execute the selected capture target"

region_box=$(sed -n '/id: selectionBox/,/MouseArea {/p' "$OVERLAY")
rg --fixed-strings --quiet -- 'color: "transparent"' <<<"$region_box" ||
  fail "the region box has a fill"
assert_absent 'visible: root.hasSelection && root.targetKind === "window"' \
  "window targets still draw a border layer"
assert_absent 'opacity: 0.72' "the Omarchy scrim color has an additional opacity multiplier"

recording_action=$(sed -n '/id: recordingActionButton/,/^        }/p' "$OVERLAY")
rg --fixed-strings --quiet -- 'visible: root.recordingMode || root.recording' <<<"$recording_action" ||
  fail "the primary action is still visible during Screenshot mode"
if rg --fixed-strings --quiet -- 'Capture' <<<"$recording_action"; then
  fail "the Screenshot-mode Capture action is still present"
fi

whole_screen_function=$(sed -n '/^  function captureWholeScreen()/,/^  }/p' "$OVERLAY")
rg --fixed-strings --quiet -- 'takeScreenshot("screen")' <<<"$whole_screen_function" ||
  fail "Space does not take a whole-screen screenshot"
if rg --fixed-strings --quiet -- 'captureScreenTarget(' <<<"$whole_screen_function"; then
  fail "Space follows Screen Recording mode instead of always taking a screenshot"
fi
assert_contains 'onActivated: root.captureWholeScreen()' "the Space shortcut is missing"

printf 'PASS: unified overlay capture interactions\n'
