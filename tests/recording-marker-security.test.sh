#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$PLUGIN_DIR/omashot"
TEST_ROOT=$(mktemp -d)
RECORDING_FILE="$TEST_ROOT/omarchy-screenrecord-filename"
SYMLINK_TARGET="$TEST_ROOT/symlink-target"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

publisher=$(sed -n '/^publish_recording_filename() {$/,/^}$/p' "$HELPER")
[[ -n $publisher ]] || fail "the secure marker publisher is missing"
eval "$publisher"

record_geometry=$(sed -n '/^record_geometry() {$/,/^}$/p' "$HELPER")
grep -Fq 'publish_recording_filename "$filename"' <<<"$record_geometry" ||
  fail "geometry recording does not use the secure marker publisher"

printf 'do not truncate\n' >"$SYMLINK_TARGET"
ln -s "$SYMLINK_TARGET" "$RECORDING_FILE"

recording="$TEST_ROOT/screenrecording.mp4"
publish_recording_filename "$recording"

[[ $(<"$SYMLINK_TARGET") == "do not truncate" ]] ||
  fail "the recording marker write followed a pre-placed symlink"
[[ -f $RECORDING_FILE && ! -L $RECORDING_FILE ]] ||
  fail "the recording marker was not atomically replaced with a regular file"
[[ $(<"$RECORDING_FILE") == "$recording" ]] ||
  fail "the recording marker does not contain the recording filename"
[[ $(stat -c '%a' "$RECORDING_FILE") == 600 ]] ||
  fail "the recording marker is not private"

printf 'PASS: recording marker resists symlink attacks\n'
