#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OVERLAY="$PLUGIN_DIR/Overlay.qml"
SUBJECT_HELPER="$PLUGIN_DIR/omashot-subject"
TEST_ROOT=$(mktemp -d)
STUB_BIN="$TEST_ROOT/bin"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

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

assert_contains 'property bool measurementMode: false' \
  "measurement mode state is missing"
assert_contains 'id: measurementModeButton' \
  "the main toolbar has no measurement toggle"
assert_contains 'readonly property string measurementIcon: "󰑭" // nf-md-ruler' \
  "the measurement toggle has no Nerd Font ruler glyph"
assert_contains 'iconText: root.measurementIcon' \
  "the measurement toggle does not render its glyph as an icon"
assert_absent 'labelText: "Measure"' \
  "the measurement toggle still uses a text label"
assert_contains 'onClicked: root.toggleMeasurementMode()' \
  "the measurement toggle is not interactive"

assert_contains 'id: horizontalMeasurementGuide' \
  "the horizontal cursor guide is missing"
assert_contains 'width: parent.width' \
  "the horizontal cursor guide is not screen-wide"
assert_contains 'id: verticalMeasurementGuide' \
  "the vertical cursor guide is missing"
assert_contains 'height: parent.height' \
  "the vertical cursor guide is not screen-high"
assert_contains 'opacity: 0.52' \
  "the cursor guides are not semi-transparent"
assert_contains 'id: measurementHover' \
  "the crosshair does not use a passive hover tracker"
assert_contains 'id: measurementPress' \
  "the crosshair does not keep tracking during pointer drags"
assert_contains 'measurementPress.point.position.x : measurementHover.point.position.x' \
  "the horizontal crosshair position is not bound directly to pointer events"
assert_contains 'measurementPress.point.position.y : measurementHover.point.position.y' \
  "the vertical crosshair position is not bound directly to pointer events"
assert_contains 'root.measurementMode ? Qt.BlankCursor : Qt.CrossCursor' \
  "the independently composited cursor is still shown over the measurement canvas"
assert_absent 'function updateMeasurementPointer(' \
  "crosshair motion still passes through the laggy JavaScript relay"

assert_contains 'id: selectionDimensions' \
  "the region dimension badge is missing"
assert_contains 'root.selectionPixelWidth + " × " + root.selectionPixelHeight + " px"' \
  "the region dimension badge does not report pixels"
assert_contains 'readonly property real lowerKnobClearance: root.resizeHandleSize + gap' \
  "the dimension badge does not clear the lower resize knobs"
assert_contains 'readonly property real lowerRightX: root.selectionX + root.selectionW + lowerKnobClearance' \
  "the dimension badge is not anchored beyond the lower-right knob"
assert_contains 'readonly property real lowerLeftX: root.selectionX - lowerKnobClearance - width' \
  "the dimension badge has no lower-left fallback"
assert_contains 'readonly property bool placeRight: lowerRightX + width <= selectionLayer.width' \
  "the dimension badge does not detect right-edge overflow"
assert_contains 'x: placeRight ? lowerRightX : Math.max(0, lowerLeftX)' \
  "the dimension badge does not flip from lower-right to lower-left"
assert_contains '? root.selectionY + root.selectionH + lowerKnobClearance' \
  "the dimension badge is not placed below the lower resize knob"

ratio_options=$(sed -n '/readonly property var aspectRatios:/,/^  ]/p' "$OVERLAY")
ratio_count=$(rg --count 'value: "(1:1|16:9|16:10|21:9|4:3)"' <<<"$ratio_options")
[[ $ratio_count == 5 ]] || fail "the five requested aspect ratios are not all available"
assert_contains 'function setAspectSelectionFromAnchor(' \
  "drawing does not honor the selected aspect ratio"
assert_contains 'function resizeSelectionWithAspect(' \
  "resize handles do not honor the selected aspect ratio"
assert_contains 'onClicked: root.toggleAspectRatio(' \
  "the aspect-ratio buttons are not interactive"
assert_absent 'tooltipText: checked ? "Remove aspect-ratio constraint" : "Constrain region to " + labelText' \
  "aspect-ratio buttons still show redundant tooltips"

for badge in topMarginBadge rightMarginBadge bottomMarginBadge leftMarginBadge; do
  assert_contains "id: $badge" "the $badge subject-margin label is missing"
done
assert_contains 'component MarginValueLabel: Item' \
  "margin values are still rendered inside a box"
assert_contains 'style: Text.Outline' \
  "margin values do not have a text outline"
assert_contains 'styleColor: Color.menu.background' \
  "margin value outlines do not use the background color"
assert_contains 'readonly property real marginLabelClearance: resizeHandleSize + Style.spacing.xs' \
  "margin values do not clear the resize handles"
assert_contains 'width: root.resizeHandleSize' \
  "resize handles do not share their size with margin-label placement"
assert_contains 'component MarginDimensionLine: Item' \
  "the reusable capped margin measurement line is missing"
for line in topMarginLine rightMarginLine bottomMarginLine leftMarginLine; do
  assert_contains "id: $line" "the $line subject-margin indicator is missing"
done
assert_contains 'id: startCap' \
  "margin measurement lines have no perpendicular starting cap"
assert_contains 'id: endCap' \
  "margin measurement lines have no perpendicular ending cap"
assert_absent 'id: detectedSubjectFrame' \
  "margin measurement still draws a rectangle around the subject"
assert_contains 'onClicked: root.toggleMarginMeasurements()' \
  "the subject-margin button is not interactive"
assert_contains 'id: marginMeasurementsButton' \
  "the measurement toolbar has no margin button"
assert_contains 'readonly property string marginMeasurementIcon: "󰍓" // nf-md-margin' \
  "the margin button has no Nerd Font margin glyph"
assert_contains 'iconText: root.marginMeasurementIcon' \
  "the margin button does not use its Nerd Font glyph"
assert_absent 'labelText: "Margins"' \
  "the margin button still uses a text label"
assert_contains 'onClicked: root.requestSubjectScan("shrink")' \
  "the fit-to-subject button is not interactive"
assert_contains 'id: autoFitButton' \
  "the measurement toolbar has no auto-fit button"
assert_contains 'readonly property string autoFitIcon: "󱣴" // nf-md-fit_to_screen' \
  "the auto-fit button has no Nerd Font fit-to-screen glyph"
assert_contains 'iconText: root.autoFitIcon' \
  "the auto-fit button does not use its Nerd Font glyph"
assert_absent 'labelText: "Auto-fit"' \
  "the auto-fit button still uses a text label"
assert_contains 'visible: root.showSelectionFrame && !root.recordingPresentation && !root.subjectScanPending' \
  "selection chrome is not hidden while subject pixels are sampled"
assert_contains 'visible: !root.pickerMode && !root.recordingPresentation && !root.subjectScanPending' \
  "the main toolbar can contaminate subject detection"

[[ -x $SUBJECT_HELPER ]] || fail "the subject detector is not executable"
bash -n "$SUBJECT_HELPER" || fail "the subject detector has invalid shell syntax"

forbidden_name="epic""ruler"
if rg --ignore-case --quiet -g '!preview*.png' -g '!tests/measurement-mode.test.sh' \
    -- "$forbidden_name" "$PLUGIN_DIR"; then
  fail "an external product name leaked into the implementation"
fi

mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/grim" <<'STUB'
#!/usr/bin/env bash

output=${!#}
case "${TEST_SUBJECT_IMAGE:-subject}" in
  subject)
    magick -size 100x80 "xc:#f0f0f0" -fill "#222222" \
      -draw "rectangle 20,10 79,69" "$output"
    ;;
  uniform)
    magick -size 100x80 "xc:#f0f0f0" "$output"
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$STUB_BIN/grim"

bounds=$(PATH="$STUB_BIN:$PATH" "$SUBJECT_HELPER" "5,6 100x80" 100 80)
jq -e '.x == 20 and .y == 10 and .width == 60 and .height == 60
  and .pixelX == 20 and .pixelY == 10 and .pixelWidth == 60 and .pixelHeight == 60
  and .captureWidth == 100 and .captureHeight == 80' <<<"$bounds" >/dev/null ||
  fail "the subject detector returned incorrect bounds: $bounds"

scaled_bounds=$(PATH="$STUB_BIN:$PATH" "$SUBJECT_HELPER" "5,6 50x40" 50 40)
jq -e '.x == 10 and .y == 5 and .width == 30 and .height == 30
  and .pixelX == 20 and .pixelY == 10 and .pixelWidth == 60 and .pixelHeight == 60
  and .captureWidth == 100 and .captureHeight == 80' <<<"$scaled_bounds" >/dev/null ||
  fail "the subject detector did not normalize scaled pixels: $scaled_bounds"

uniform=$(TEST_SUBJECT_IMAGE=uniform PATH="$STUB_BIN:$PATH" \
  "$SUBJECT_HELPER" "5,6 100x80" 100 80 2>/dev/null)
[[ $uniform == null ]] || fail "a uniform region was mistaken for a subject"

printf 'PASS: measurement-assisted region selection\n'
