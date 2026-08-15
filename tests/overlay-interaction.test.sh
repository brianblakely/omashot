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
rg --fixed-strings --quiet -- 'value: "recording", label: "Screen Recording"' <<<"$mode_options" ||
  fail "the Screen Recording mode is missing"

assert_contains 'property string captureKind: "screenshot"' \
  "the overlay does not initialize in Screenshot mode"
assert_contains 'captureKind = "screenshot"' \
  "opening the normal overlay does not reset it to Screenshot mode"
assert_absent 'captureModes' "the legacy five-button mode model is still present"
assert_absent 'selectedMode' "capture type is still coupled to legacy target modes"

assert_contains 'function updateTargetHover(' "window hover targeting is missing"
assert_contains 'var client = clientAt(' "hover targeting does not inspect the window under the pointer"
assert_contains 'if (isPointAtTopEdge(y))' "top-edge screen targeting is missing"
assert_contains 'root.beginTargetPointer(' "pointer presses do not use unified target selection"
assert_contains 'onReleased: root.finishTargetPointer(' "pointer clicks do not execute unified targets"
assert_contains 'pointerAction = "draw"' "pointer drags cannot create a region"
assert_contains 'targetKind = "region"' "dragged selections are not marked as regions"
assert_contains 'root.captureSelectedTarget(panel.currentScreenName)' \
  "Enter does not execute the selected capture target"

whole_screen_function=$(sed -n '/^  function captureWholeScreen()/,/^  }/p' "$OVERLAY")
rg --fixed-strings --quiet -- 'takeScreenshot("screen")' <<<"$whole_screen_function" ||
  fail "Space does not take a whole-screen screenshot"
if rg --fixed-strings --quiet -- 'captureScreenTarget(' <<<"$whole_screen_function"; then
  fail "Space follows Screen Recording mode instead of always taking a screenshot"
fi
assert_contains 'onActivated: root.captureWholeScreen()' "the Space shortcut is missing"

printf 'PASS: unified overlay capture interactions\n'
