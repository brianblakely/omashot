#!/usr/bin/env bash

set -euo pipefail

PLUGIN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

STATE_DIR="$TEST_ROOT/state"
RECORDING_ESCAPE_MARKER="$STATE_DIR/recording-escape-bound"

# Capture the actual Lua sent by all three helpers without touching Hyprland.
source <(sed -n '/^install_recording_escape_binding() {$/,/^recording_session_locked() {$/p' \
  "$PLUGIN_DIR/omashot" | sed '$d')

hyprctl() {
  [[ $1 == eval ]]
  printf '%s\n' "$2" >"$TEST_LUA_FILE"
}

TEST_LUA_FILE="$TEST_ROOT/immediate.lua"
install_recording_escape_binding
TEST_LUA_FILE="$TEST_ROOT/keystrokes.lua"
install_recording_keystroke_bindings
TEST_LUA_FILE="$TEST_ROOT/cleanup.lua"
remove_recording_escape_binding

lua - "$TEST_ROOT/immediate.lua" "$TEST_ROOT/keystrokes.lua" "$TEST_ROOT/cleanup.lua" <<'LUA'
local installers = { immediate = assert(loadfile(arg[1])), keystrokes = assert(loadfile(arg[2])) }
local cleanup = assert(loadfile(arg[3]))
local counts = { immediate = 1, keystrokes = 103 }
local created = {}
local trackers = {}

local methods = {}
function methods:set_enabled(value)
  assert(not self.expired, "set_enabled touched an expired keybind")
  self.enabled = value
end
function methods:is_enabled()
  assert(not self.expired, "is_enabled touched an expired keybind")
  return self.enabled
end
function methods:remove() error("unbind can remove unrelated user shortcuts") end
methods.unbind = methods.remove

local function new_binding()
  local binding = setmetatable({ enabled = true, expired = false }, {
    __index = methods,
    __tostring = function(self)
      return self.expired and "HL.Keybind(expired)" or "HL.Keybind(0x1234)"
    end,
  })
  table.insert(created, binding)
  return binding
end

hl = { dsp = {} }
function hl.dsp.exec_cmd(value) return value end
function hl.dsp.global(value) return value end
function hl.dsp.event(value) return value end
function hl.bind() return new_binding() end
function hl.is_key_down() return false end
function hl.timer()
  local timer = { enabled = true }
  function timer:set_enabled(value) self.enabled = value end
  table.insert(trackers, timer)
  return timer
end
function hl.on()
  local subscription = { active = true }
  function subscription:is_active() return self.active end
  function subscription:remove() self.active = false end
  table.insert(trackers, subscription)
  return subscription
end
function hl.unbind() error("unbind can remove unrelated user shortcuts") end

local function reset()
  created = {}
  trackers = {}
  omashot_recording_binding_sets = nil
  omashot_recording_keybinds = nil
  omashot_recording_escape_bind = nil
  omashot_recording_modifier_tracker = nil
end

local function reload()
  -- A config reload destroys the underlying keybinds but leaves Lua globals.
  for _, binding in ipairs(created) do binding.expired = true end
end

local function assert_enabled(expected)
  local enabled = 0
  for _, binding in ipairs(created) do
    if not binding.expired and binding.enabled then enabled = enabled + 1 end
  end
  assert(enabled == expected, "wrong number of active recording shortcuts: " .. enabled)
end

local function assert_clean()
  assert_enabled(0)
  assert(omashot_recording_modifier_tracker == nil)
  for _, tracker in ipairs(trackers) do
    assert(not tracker.enabled and not tracker.active, "modifier tracker survived cleanup")
  end
end

for mode, install in pairs(installers) do
  reset()
  for _ = 1, 3 do
    install()
    assert_enabled(counts[mode])
    cleanup()
    assert_clean()
  end
  assert(#created == counts[mode], "repeated recordings accumulated duplicate bindings")

  reload()
  install()
  assert_enabled(counts[mode])
  assert(#created == counts[mode] * 2, "stale binding set was not rebuilt")

  -- Reload during an active recording, then stop (also used on lock/exit).
  reload()
  cleanup()
  assert_clean()
  cleanup()
  install()
  assert_enabled(counts[mode])
  cleanup()
  assert_clean()

  -- Both installers must tolerate the other mode's expired cached set.
  for next_mode, next_install in pairs(installers) do
    reset()
    install()
    reload()
    next_install()
    assert_enabled(counts[next_mode])
    cleanup()
    assert_clean()
  end
end

-- Validate the entire set, including a dead handle after live ones.
reset()
installers.keystrokes()
created[#created].expired = true
installers.keystrokes()
assert_enabled(counts.keystrokes)
cleanup()
assert_clean()

-- An upgrade may leave either legacy global populated. Exercise every entry
-- point with live and expired handles; no method on an expired handle is safe.
for _, operation in ipairs({ installers.immediate, installers.keystrokes, cleanup }) do
  for _, expired in ipairs({ false, true }) do
    reset()
    local legacy = new_binding()
    legacy.expired = expired
    omashot_recording_keybinds = { legacy }
    omashot_recording_escape_bind = new_binding()
    omashot_recording_escape_bind.expired = expired
    operation()
    assert(omashot_recording_keybinds == nil and omashot_recording_escape_bind == nil)
    cleanup()
    assert_clean()
  end
end

print("PASS: recording bindings survive Hyprland config reloads")
LUA
