#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$PLUGIN_DIR/omashot"
TEST_ROOT=$(mktemp -d)
RUNTIME_DIR="$TEST_ROOT"
RECORDING_FILE="$TEST_ROOT/omarchy-screenrecord-filename"
RECORDING_PID_FILE="$TEST_ROOT/omarchy-screenrecord-pid"
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

pid_publisher=$(sed -n '/^publish_recording_pid() {$/,/^}$/p' "$HELPER")
[[ -n $pid_publisher ]] || fail "the secure pid publisher is missing"
eval "$pid_publisher"

record_geometry=$(sed -n '/^record_geometry() {$/,/^}$/p' "$HELPER")
grep -Fq 'publish_recording_pid "$pid"' <<<"$record_geometry" ||
  fail "geometry recording never publishes the recorder pid, so --stop-recording cannot find it"
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

# The pid file is read back by Omarchy's stop path to signal the recorder, so it
# needs the same treatment: a private regular file, never a followed symlink.
pid_target="$TEST_ROOT/pid-target"
printf 'do not truncate\n' >"$pid_target"
ln -s "$pid_target" "$RECORDING_PID_FILE"

publish_recording_pid 4242

[[ $(<"$pid_target") == "do not truncate" ]] ||
  fail "the pid write followed a pre-placed symlink"
[[ -f $RECORDING_PID_FILE && ! -L $RECORDING_PID_FILE ]] ||
  fail "the pid file was not atomically replaced with a regular file"
[[ $(<"$RECORDING_PID_FILE") == "4242" ]] ||
  fail "the pid file does not contain the recorder pid"
[[ $(stat -c '%a' "$RECORDING_PID_FILE") == 600 ]] ||
  fail "the pid file is not private"

# A pid that is not a plain positive integer is refused, not written.
if publish_recording_pid "1; rm -rf /" 2>/dev/null; then
  fail "the pid publisher accepted a non-numeric pid"
fi

printf 'PASS: recording marker resists symlink attacks\n'
