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

assert_contains 'property bool measurementMode: false' \
  "measurement mode state is missing"
assert_contains 'id: measurementModeButton' \
  "the main toolbar has no measurement toggle"
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

assert_contains 'id: selectionDimensions' \
  "the region dimension badge is missing"
assert_contains 'root.selectionPixelWidth + " × " + root.selectionPixelHeight + " px"' \
  "the region dimension badge does not report pixels"
assert_contains '? root.selectionY + root.selectionH + gap' \
  "the dimension badge is not placed below the region when space permits"

ratio_options=$(sed -n '/readonly property var aspectRatios:/,/^  ]/p' "$OVERLAY")
ratio_count=$(rg --count 'value: "(1:1|16:9|16:10|21:9|4:3)"' <<<"$ratio_options")
[[ $ratio_count == 5 ]] || fail "the five requested aspect ratios are not all available"
assert_contains 'function setAspectSelectionFromAnchor(' \
  "drawing does not honor the selected aspect ratio"
assert_contains 'function resizeSelectionWithAspect(' \
  "resize handles do not honor the selected aspect ratio"
assert_contains 'onClicked: root.toggleAspectRatio(' \
  "the aspect-ratio buttons are not interactive"

for badge in topMarginBadge rightMarginBadge bottomMarginBadge leftMarginBadge; do
  assert_contains "id: $badge" "the $badge subject-margin label is missing"
done
assert_contains 'onClicked: root.toggleMarginMeasurements()' \
  "the subject-margin button is not interactive"
assert_contains 'onClicked: root.requestSubjectScan("shrink")' \
  "the fit-to-subject button is not interactive"
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
