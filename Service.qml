pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "b.omashot"
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir ? sourceDir + "/omashot" : Qt.resolvedUrl("omashot").toString().replace(/^file:\/\//, "")

  readonly property var pluginSettings: currentSettings()
  readonly property string captureMode: setting("captureMode", "selection")
  readonly property string outputMode: setting("outputMode", "file-and-clipboard")
  readonly property string saveLocation: normalizeSaveLocation(setting("saveLocation", "pictures"))
  readonly property int timerSeconds: clampInt(setting("timerSeconds", 0), 0, 60)
  readonly property bool includeCursor: setting("includeCursor", false) === true
  readonly property bool recordDesktopAudio: setting("recordDesktopAudio", false) === true
  readonly property bool recordMicrophoneAudio: setting("recordMicrophoneAudio", false) === true
  readonly property bool recordWebcam: setting("recordWebcam", false) === true
  readonly property bool recordKeystrokes: setting("recordKeystrokes", false) === true
  readonly property bool measurementModeEnabled: setting("measurementModeEnabled", false) === true

  property bool recording: false
  property string lastStatus: "{}"
  property var pendingCaptureArgs: null
  property bool pendingCaptureKeepsOverlay: false
  property string recordingTargetScreenName: ""
  property string recordingTargetGeometry: ""
  property int recordingTargetX: 0
  property int recordingTargetY: 0
  property int recordingTargetW: 0
  property int recordingTargetH: 0
  property var keystrokeEntries: []
  property var pressedKeystrokes: ({})
  property var pressedModifiers: ({})
  property double lastKeystrokeAt: 0
  property bool escapeHeld: false
  property bool escapeHoldCompleted: false
  property string escapePassModifiers: ""

  readonly property bool keystrokeOverlayVisible: recording && recordKeystrokes
    && recordingTargetW > 0 && recordingTargetH > 0
  readonly property var keystrokeCatalog: [
    { shortcut: "key-a", label: "A" },
    { shortcut: "key-b", label: "B" },
    { shortcut: "key-c", label: "C" },
    { shortcut: "key-d", label: "D" },
    { shortcut: "key-e", label: "E" },
    { shortcut: "key-f", label: "F" },
    { shortcut: "key-g", label: "G" },
    { shortcut: "key-h", label: "H" },
    { shortcut: "key-i", label: "I" },
    { shortcut: "key-j", label: "J" },
    { shortcut: "key-k", label: "K" },
    { shortcut: "key-l", label: "L" },
    { shortcut: "key-m", label: "M" },
    { shortcut: "key-n", label: "N" },
    { shortcut: "key-o", label: "O" },
    { shortcut: "key-p", label: "P" },
    { shortcut: "key-q", label: "Q" },
    { shortcut: "key-r", label: "R" },
    { shortcut: "key-s", label: "S" },
    { shortcut: "key-t", label: "T" },
    { shortcut: "key-u", label: "U" },
    { shortcut: "key-v", label: "V" },
    { shortcut: "key-w", label: "W" },
    { shortcut: "key-x", label: "X" },
    { shortcut: "key-y", label: "Y" },
    { shortcut: "key-z", label: "Z" },
    { shortcut: "key-0", label: "0" },
    { shortcut: "key-1", label: "1" },
    { shortcut: "key-2", label: "2" },
    { shortcut: "key-3", label: "3" },
    { shortcut: "key-4", label: "4" },
    { shortcut: "key-5", label: "5" },
    { shortcut: "key-6", label: "6" },
    { shortcut: "key-7", label: "7" },
    { shortcut: "key-8", label: "8" },
    { shortcut: "key-9", label: "9" },
    { shortcut: "key-space", label: "Space", glyph: "󱁐" },
    { shortcut: "key-grave", label: "`" },
    { shortcut: "key-minus", label: "-" },
    { shortcut: "key-equal", label: "=" },
    { shortcut: "key-bracket-left", label: "[" },
    { shortcut: "key-bracket-right", label: "]" },
    { shortcut: "key-backslash", label: "\\" },
    { shortcut: "key-semicolon", label: ";" },
    { shortcut: "key-apostrophe", label: "'" },
    { shortcut: "key-comma", label: "," },
    { shortcut: "key-period", label: "." },
    { shortcut: "key-slash", label: "/" },
    { shortcut: "key-tab", label: "Tab", glyph: "󰌒" },
    { shortcut: "key-enter", label: "Enter", glyph: "󰌑" },
    { shortcut: "key-backspace", label: "Backspace", glyph: "󰌍" },
    { shortcut: "key-insert", label: "Insert", glyph: "" },
    { shortcut: "key-delete", label: "Delete", glyph: "󰆴" },
    { shortcut: "key-home", label: "Home", glyph: "󰋜" },
    { shortcut: "key-end", label: "End", glyph: "󰘁" },
    { shortcut: "key-page-up", label: "Page Up", glyph: "󰞕" },
    { shortcut: "key-page-down", label: "Page Down", glyph: "󰞒" },
    { shortcut: "key-left", label: "Left", glyph: "󰁍" },
    { shortcut: "key-right", label: "Right", glyph: "󰁔" },
    { shortcut: "key-up", label: "Up", glyph: "󰁝" },
    { shortcut: "key-down", label: "Down", glyph: "󰁅" },
    { shortcut: "key-caps-lock", label: "Caps Lock", glyph: "󰘲" },
    { shortcut: "key-num-lock", label: "Num Lock", glyph: "󰎠" },
    { shortcut: "key-print", label: "Print Screen", glyph: "󰐪" },
    { shortcut: "key-pause", label: "Pause", glyph: "󰏤" },
    { shortcut: "key-f1", label: "F1", glyph: "󱊫" },
    { shortcut: "key-f2", label: "F2", glyph: "󱊬" },
    { shortcut: "key-f3", label: "F3", glyph: "󱊭" },
    { shortcut: "key-f4", label: "F4", glyph: "󱊮" },
    { shortcut: "key-f5", label: "F5", glyph: "󱊯" },
    { shortcut: "key-f6", label: "F6", glyph: "󱊰" },
    { shortcut: "key-f7", label: "F7", glyph: "󱊱" },
    { shortcut: "key-f8", label: "F8", glyph: "󱊲" },
    { shortcut: "key-f9", label: "F9", glyph: "󱊳" },
    { shortcut: "key-f10", label: "F10", glyph: "󱊴" },
    { shortcut: "key-f11", label: "F11", glyph: "󱊵" },
    { shortcut: "key-f12", label: "F12", glyph: "󱊶" },
    { shortcut: "key-kp-0", label: "Num 0" },
    { shortcut: "key-kp-1", label: "Num 1" },
    { shortcut: "key-kp-2", label: "Num 2" },
    { shortcut: "key-kp-3", label: "Num 3" },
    { shortcut: "key-kp-4", label: "Num 4" },
    { shortcut: "key-kp-5", label: "Num 5" },
    { shortcut: "key-kp-6", label: "Num 6" },
    { shortcut: "key-kp-7", label: "Num 7" },
    { shortcut: "key-kp-8", label: "Num 8" },
    { shortcut: "key-kp-9", label: "Num 9" },
    { shortcut: "key-kp-decimal", label: "Num ." },
    { shortcut: "key-kp-divide", label: "Num /" },
    { shortcut: "key-kp-multiply", label: "Num *" },
    { shortcut: "key-kp-subtract", label: "Num -" },
    { shortcut: "key-kp-add", label: "Num +" },
    { shortcut: "key-kp-enter", label: "Num Enter", glyph: "󰌑" },
    { shortcut: "key-kp-equal", label: "Num =" },
    { shortcut: "key-escape", label: "Escape", glyph: "󱊷", kind: "escape" },
    { shortcut: "modifier-ctrl-left", label: "Ctrl", glyph: "󰘴", kind: "modifier", modifier: "ctrl" },
    { shortcut: "modifier-ctrl-right", label: "Ctrl", glyph: "󰘴", kind: "modifier", modifier: "ctrl" },
    { shortcut: "modifier-shift-left", label: "Shift", glyph: "󰘶", kind: "modifier", modifier: "shift" },
    { shortcut: "modifier-shift-right", label: "Shift", glyph: "󰘶", kind: "modifier", modifier: "shift" },
    { shortcut: "modifier-alt-left", label: "Alt", glyph: "󰘵", kind: "modifier", modifier: "alt" },
    { shortcut: "modifier-alt-right", label: "Alt", glyph: "󰘵", kind: "modifier", modifier: "alt" },
    { shortcut: "modifier-super-left", label: "Super", glyph: "\ue900", fontFamily: "omarchy", kind: "modifier", modifier: "super" },
    { shortcut: "modifier-super-right", label: "Super", glyph: "\ue900", fontFamily: "omarchy", kind: "modifier", modifier: "super" }
  ]

  signal recordingPresentationRequested()

  function clampInt(value, min, max) {
    var parsed = parseInt(value, 10)
    if (!isFinite(parsed)) parsed = min
    return Math.max(min, Math.min(max, parsed))
  }

  function normalizeSaveLocation(value) {
    var requested = String(value || "pictures")
    var symbolic = requested.toLowerCase()
    if (symbolic === "pictures" || symbolic === "videos"
        || symbolic === "documents" || symbolic === "downloads") return symbolic
    if (requested.charAt(0) === "/") return requested
    return "pictures"
  }

  function currentSettings() {
    var config = shell && shell.shellConfig ? shell.shellConfig : null
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      var entry = plugins[i]
      if (entry && String(entry.id || "") === pluginId) return entry
    }
    return {}
  }

  function setting(name, fallback) {
    var value = pluginSettings ? pluginSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function saveSettings(nextValues) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false

    var next = {}
    var current = pluginSettings || {}
    for (var key in current) {
      if (key !== "id") next[key] = current[key]
    }
    for (var nkey in nextValues) {
      if (nkey !== "id") next[nkey] = nextValues[nkey]
    }

    return shell.updateEntryInline(pluginId, next)
  }

  function captureContext(geometry, screenName, outputOverride, freezePid, targetGeometry, modifiers) {
    var context = ({})
    var selectedGeometry = String(geometry || "").replace(/^\s+|\s+$/g, "")
    var selectedScreen = String(screenName || "")
    var selectedOutput = String(outputOverride || "")
    var selectedTargetGeometry = String(targetGeometry || "").replace(/^\s+|\s+$/g, "")
    var selectedModifiers = String(modifiers || "")
    var pid = Math.floor(Number(freezePid))

    if (selectedGeometry !== "") context.geometry = selectedGeometry
    if (selectedScreen !== "") context.screenName = selectedScreen
    if (selectedOutput !== "") context.action = selectedOutput
    if (selectedTargetGeometry !== "") context.targetGeometry = selectedTargetGeometry
    if (selectedModifiers !== "") context.modifiers = selectedModifiers
    if (isFinite(pid) && pid > 0) context.freezePid = pid
    return JSON.stringify(context)
  }

  function booleanValue(value) {
    return value === true || String(value).toLowerCase() === "true"
  }

  function setRecordingTarget(geometry, screenName) {
    var value = String(geometry || "").replace(/^\s+|\s+$/g, "")
    var match = value.match(/^(-?\d+),(-?\d+)\s+(\d+)x(\d+)$/)
    if (!match || Number(match[3]) <= 0 || Number(match[4]) <= 0) return false

    recordingTargetGeometry = value
    recordingTargetScreenName = String(screenName || "")
    recordingTargetX = Number(match[1])
    recordingTargetY = Number(match[2])
    recordingTargetW = Number(match[3])
    recordingTargetH = Number(match[4])
    return true
  }

  function clearRecordingTarget() {
    recordingTargetScreenName = ""
    recordingTargetGeometry = ""
    recordingTargetX = 0
    recordingTargetY = 0
    recordingTargetW = 0
    recordingTargetH = 0
  }

  function activeModifierNames() {
    var active = ({ ctrl: false, shift: false, alt: false, super: false })
    var modifiers = pressedModifiers || ({})
    for (var shortcut in modifiers) {
      var name = String(modifiers[shortcut] || "")
      if (active[name] !== undefined) active[name] = true
    }

    var labels = []
    if (active.ctrl) labels.push("Ctrl")
    if (active.shift) labels.push("Shift")
    if (active.alt) labels.push("Alt")
    if (active.super) labels.push("Super")
    return labels
  }

  function activeModifierDispatch() {
    var labels = activeModifierNames()
    var dispatch = []
    for (var i = 0; i < labels.length; i++) dispatch.push(labels[i].toUpperCase())
    return dispatch.join(" + ")
  }

  function modifierDisplay(name) {
    var requested = String(name || "").toLowerCase()
    for (var i = 0; i < keystrokeCatalog.length; i++) {
      var entry = keystrokeCatalog[i]
      if (String(entry.modifier || "") === requested && entry.glyph)
        return {
          text: String(entry.glyph),
          fontFamily: String(entry.fontFamily || "")
        }
    }
    return { text: String(name || ""), fontFamily: "" }
  }

  function activeModifierDisplays() {
    var names = activeModifierNames()
    var displays = []
    for (var i = 0; i < names.length; i++) displays.push(modifierDisplay(names[i]))
    return displays
  }

  function appendKeystroke(label, repeated, fontFamily) {
    var now = Date.now()
    var entries = keystrokeEntries.slice(0)
    if (lastKeystrokeAt <= 0 || now - lastKeystrokeAt > 500) entries = []

    var chord = activeModifierDisplays()
    chord.push({ text: String(label || ""), fontFamily: String(fontFamily || "") })
    var labels = []
    var displayParts = []
    for (var i = 0; i < chord.length; i++) {
      if (i > 0) displayParts.push({ text: " + ", fontFamily: "" })
      labels.push(String(chord[i].text || ""))
      displayParts.push({
        text: String(chord[i].text || ""),
        fontFamily: String(chord[i].fontFamily || "")
      })
    }
    var text = labels.join(" + ")
    var last = entries.length > 0 ? entries[entries.length - 1] : null
    if (repeated === true && last && String(last.text || "") === text) {
      entries[entries.length - 1] = {
        text: text,
        parts: displayParts,
        count: Math.max(1, Number(last.count) || 1) + 1
      }
    } else {
      entries.push({ text: text, parts: displayParts, count: 1 })
    }

    // Width trimming is authoritative, but this also bounds retained state if
    // outputs disappear while a recording is active.
    if (entries.length > 64) entries = entries.slice(entries.length - 64)
    keystrokeEntries = entries
    lastKeystrokeAt = now
    keystrokeClearTimer.restart()
  }

  function trimKeystrokes(contentWidth, availableWidth) {
    var content = Number(contentWidth)
    var available = Number(availableWidth)
    if (!isFinite(content) || !isFinite(available) || content <= available
        || keystrokeEntries.length <= 1) return false

    keystrokeEntries = keystrokeEntries.slice(1)
    return true
  }

  function beginEscapeHold() {
    if (escapeHeld) return
    escapeHeld = true
    escapeHoldCompleted = false
    escapePassModifiers = activeModifierDispatch()
    escapeHoldTimer.restart()
  }

  function endEscapeHold() {
    if (!escapeHeld) return

    var shouldPass = !escapeHoldCompleted && recording && recordKeystrokes
    var modifiers = escapePassModifiers
    escapeHeld = false
    escapeHoldCompleted = false
    escapePassModifiers = ""
    escapeHoldTimer.stop()

    if (shouldPass)
      runDetached(["pass-escape", "", captureContext("", "", "", "", "", modifiers)])
  }

  function keystrokePressed(entry) {
    if (!recording || !recordKeystrokes || !entry) return

    var shortcut = String(entry.shortcut || "")
    if (String(entry.kind || "") === "modifier") {
      var modifiers = ({})
      for (var modifierKey in pressedModifiers) modifiers[modifierKey] = pressedModifiers[modifierKey]
      modifiers[shortcut] = String(entry.modifier || "")
      pressedModifiers = modifiers
      return
    }

    var wasPressed = pressedKeystrokes[shortcut] === true
    var pressed = ({})
    for (var key in pressedKeystrokes) pressed[key] = pressedKeystrokes[key]
    pressed[shortcut] = true
    pressedKeystrokes = pressed
    appendKeystroke(entry.glyph || entry.label, wasPressed, entry.fontFamily)

    if (String(entry.kind || "") === "escape") beginEscapeHold()
  }

  function keystrokeReleased(entry) {
    if (!entry) return

    var shortcut = String(entry.shortcut || "")
    if (String(entry.kind || "") === "modifier") {
      var modifiers = ({})
      for (var modifierKey in pressedModifiers) {
        if (modifierKey !== shortcut) modifiers[modifierKey] = pressedModifiers[modifierKey]
      }
      pressedModifiers = modifiers
      return
    }

    var pressed = ({})
    for (var key in pressedKeystrokes) {
      if (key !== shortcut) pressed[key] = pressedKeystrokes[key]
    }
    pressedKeystrokes = pressed
    if (String(entry.kind || "") === "escape") endEscapeHold()
  }

  function setPhysicalModifierState(shortcut, pressed) {
    var requested = String(shortcut || "")
    for (var i = 0; i < keystrokeCatalog.length; i++) {
      var entry = keystrokeCatalog[i]
      if (String(entry.kind || "") !== "modifier"
          || String(entry.shortcut || "") !== requested) continue

      var alreadyPressed = pressedModifiers[requested] !== undefined
      if (pressed === alreadyPressed) return
      if (pressed === true) keystrokePressed(entry)
      else keystrokeReleased(entry)
      return
    }
  }

  function handleHyprlandEvent(event) {
    if (String(event && event.name ? event.name : "") !== "custom") return

    var fields = String(event && event.data ? event.data : "").split(",")
    if (fields.length !== 3 || fields[0] !== "b.omashot-modifier") return
    if (fields[2] !== "0" && fields[2] !== "1") return
    setPhysicalModifierState(fields[1], fields[2] === "1")
  }

  function clearKeystrokeState(clearTarget) {
    keystrokeClearTimer.stop()
    escapeHoldTimer.stop()
    keystrokeEntries = []
    pressedKeystrokes = ({})
    pressedModifiers = ({})
    lastKeystrokeAt = 0
    escapeHeld = false
    escapeHoldCompleted = false
    escapePassModifiers = ""
    if (clearTarget === true) clearRecordingTarget()
  }

  function applyRecorderStatus(raw) {
    lastStatus = String(raw || "{}").trim() || "{}"
    var parsed = ({})
    try { parsed = JSON.parse(lastStatus) || ({}) } catch (e) { parsed = ({}) }

    var active = parsed.recording === true
    if (active && !recording) clearKeystrokeState(false)
    if (active && parsed.recordingGeometry)
      setRecordingTarget(parsed.recordingGeometry, parsed.recordingScreenName)
    recording = active
    if (!active) clearKeystrokeState(true)
  }

  function runDetached(args) {
    if (!helperPath) return "missing-helper"
    Quickshell.execDetached(["bash", helperPath].concat(args))
    return "ok"
  }

  function launchCapture(args, keepOverlay) {
    if (keepOverlay === true) recordingPresentationRequested()
    else hide()
    return runDetached(args)
  }

  function runCapture(args, includeDemo, keepOverlay) {
    if (!helperPath) return "missing-helper"

    if (includeDemo !== true) {
      return launchCapture(args, keepOverlay)
    }

    if (demoScreenshotProc.running) return "busy"

    pendingCaptureArgs = args.slice(0)
    pendingCaptureKeepsOverlay = keepOverlay === true
    demoScreenshotProc.command = ["bash", helperPath, "demo-screenshot"]
    demoScreenshotProc.running = true
    return "ok"
  }

  function show() {
    if (shell && typeof shell.summon === "function")
      return shell.summon(pluginId, "{}") ? "ok" : "unknown"
    return "unknown"
  }

  function hide() {
    if (shell && typeof shell.hide === "function") {
      shell.hide(pluginId)
      return "ok"
    }
    return "unknown"
  }

  function toggle() {
    if (shell && typeof shell.toggle === "function") {
      shell.toggle(pluginId, "{}")
      return "ok"
    }
    return "unknown"
  }

  function showTargetPicker(action, regionOnly) {
    if (shell && typeof shell.summon === "function") {
      var payload = JSON.stringify({
        action: String(action || "file"),
        regionOnly: regionOnly === true
      })
      return shell.summon(pluginId, payload) ? "ok" : "unknown"
    }
    return "unknown"
  }

  function showRegionPicker(action) {
    return showTargetPicker(action || "file", true)
  }

  function screenshot(mode, outputOverride, freezePid, includeDemo) {
    var target = String(mode || captureMode || "selection")
    saveSettings({ captureMode: target })
    return runCapture(["screenshot", target, captureContext("", "", outputOverride, freezePid)], includeDemo)
  }

  function screenshotGeometry(geometry, screenName, outputOverride, captureModeOverride, freezePid, includeDemo) {
    var selectedGeometry = String(geometry || "").replace(/^\s+|\s+$/g, "")
    if (selectedGeometry === "") return "missing-geometry"

    saveSettings({ captureMode: String(captureModeOverride || "selection") })
    return runCapture(["screenshot", "selection",
      captureContext(selectedGeometry, screenName, outputOverride, freezePid)], includeDemo)
  }

  function recordGeometry(geometry, screenName, includeDemo) {
    var selectedGeometry = String(geometry || "").replace(/^\s+|\s+$/g, "")
    if (selectedGeometry === "") return "missing-geometry"

    clearKeystrokeState(true)
    saveSettings({ captureMode: "record-selection" })
    return runCapture(["record", "selection",
      captureContext(selectedGeometry, screenName, "", "")], includeDemo, true)
  }

  function record(mode, includeDemo, screenName, targetGeometry) {
    var target = String(mode || "selection")
    clearKeystrokeState(true)
    saveSettings({ captureMode: target === "screen" ? "record-screen" : "record-selection" })
    return runCapture(["record", target,
      captureContext("", screenName, "", "", targetGeometry)], includeDemo)
  }

  function stopRecording() {
    clearKeystrokeState(true)
    hide()
    return runDetached(["stop-recording"])
  }

  function toggleRecording() {
    if (recording) clearKeystrokeState(true)
    hide()
    return runDetached(["toggle-recording", "selection", captureContext("", "", "", "")])
  }

  function captureToFile() {
    return showTargetPicker("file")
  }

  function captureToClipboard() {
    return showTargetPicker("clipboard")
  }

  function recordPicker() {
    return showTargetPicker("record")
  }

  function captureSelection() {
    return showRegionPicker("file")
  }

  function copySelection() {
    return showRegionPicker("clipboard")
  }

  function recordSelection() {
    return showRegionPicker("record")
  }

  function openLast() {
    return runDetached(["open-last"])
  }

  function statusJson() {
    return JSON.stringify({
      recording: recording,
      captureMode: captureMode,
      outputMode: outputMode,
      saveLocation: saveLocation,
      timerSeconds: timerSeconds,
      includeCursor: includeCursor,
      recordDesktopAudio: recordDesktopAudio,
      recordMicrophoneAudio: recordMicrophoneAudio,
      recordWebcam: recordWebcam,
      recordKeystrokes: recordKeystrokes,
      measurementModeEnabled: measurementModeEnabled,
      recordingTargetScreenName: recordingTargetScreenName,
      recordingTargetGeometry: recordingTargetGeometry,
      helperPath: helperPath,
      lastStatus: lastStatus
    })
  }

  function refreshStatus() {
    if (statusProc.running || !helperPath) return
    statusProc.command = ["bash", helperPath, "status"]
    statusProc.running = true
  }

  function setCaptureMode(value) {
    var next = String(value || "selection")
    saveSettings({ captureMode: next })
    return next
  }

  function setOutputMode(value) {
    var next = String(value || "file-and-clipboard")
    saveSettings({ outputMode: next })
    return next
  }

  function setSaveLocation(value) {
    var next = normalizeSaveLocation(value)
    saveSettings({ saveLocation: next })
    return next
  }

  function setTimer(value) {
    var next = clampInt(value, 0, 60)
    saveSettings({ timerSeconds: next })
    return String(next)
  }

  function setIncludeCursor(value) {
    var next = booleanValue(value)
    saveSettings({ includeCursor: next })
    return next ? "true" : "false"
  }

  function setMeasurementModeEnabled(value) {
    var next = booleanValue(value)
    saveSettings({ measurementModeEnabled: next })
    return next ? "true" : "false"
  }

  function setRecordDesktopAudio(value) {
    var next = booleanValue(value)
    saveSettings({ recordDesktopAudio: next })
    return next ? "true" : "false"
  }

  function setRecordMicrophoneAudio(value) {
    var next = booleanValue(value)
    saveSettings({ recordMicrophoneAudio: next })
    return next ? "true" : "false"
  }

  function setRecordWebcam(value) {
    var next = booleanValue(value)
    saveSettings({ recordWebcam: next })
    return next ? "true" : "false"
  }

  function setRecordKeystrokes(value) {
    var next = booleanValue(value)
    saveSettings({ recordKeystrokes: next })
    if (!next) clearKeystrokeState(false)
    if (recording) runDetached(["sync-recording-input", next ? "true" : "false"])
    return next ? "true" : "false"
  }

  Timer {
    id: keystrokeClearTimer
    interval: 2000
    repeat: false
    onTriggered: root.keystrokeEntries = []
  }

  Timer {
    id: escapeHoldTimer
    interval: 2000
    repeat: false
    onTriggered: {
      if (!root.escapeHeld || !root.recording || !root.recordKeystrokes) return
      root.escapeHoldCompleted = true
      root.stopRecording()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Repeater {
    model: root.keystrokeCatalog

    Item {
      id: keystrokeShortcutDelegate
      required property var modelData
      visible: false

      GlobalShortcut {
        appid: root.pluginId
        name: keystrokeShortcutDelegate.modelData.shortcut
        description: "Omashot recording key: " + keystrokeShortcutDelegate.modelData.label
        onPressed: root.keystrokePressed(keystrokeShortcutDelegate.modelData)
        onReleased: root.keystrokeReleased(keystrokeShortcutDelegate.modelData)
      }
    }
  }

  KeystrokeOverlay {
    service: root
  }

  Component.onDestruction: root.runDetached(["cleanup-recording-input"])

  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Process {
    id: demoScreenshotProc

    onExited: function() {
      var args = root.pendingCaptureArgs
      var keepOverlay = root.pendingCaptureKeepsOverlay
      root.pendingCaptureArgs = null
      root.pendingCaptureKeepsOverlay = false
      if (args && args.length > 0) root.launchCapture(args, keepOverlay)
    }
  }

  Process {
    id: statusProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.applyRecorderStatus(text)
      }
    }
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "show"
    description: "Show Omashot"
    onPressed: root.show()
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "capture-screen"
    description: "Omashot capture screen"
    onPressed: root.screenshot("screen")
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "capture-selection"
    description: "Omashot capture region"
    onPressed: root.captureSelection()
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "capture-window"
    description: "Omashot capture window"
    onPressed: root.screenshot("window")
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "copy-screen"
    description: "Omashot copy screen"
    onPressed: root.screenshot("screen", "clipboard")
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "copy-selection"
    description: "Omashot copy region"
    onPressed: root.copySelection()
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "record-screen"
    description: "Omashot record screen"
    onPressed: root.record("screen")
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "record-selection"
    description: "Omashot record region"
    onPressed: root.recordSelection()
  }

  GlobalShortcut {
    appid: root.pluginId
    name: "stop-recording"
    description: "Omashot stop recording"
    onPressed: root.stopRecording()
  }

  IpcHandler {
    target: root.pluginId

    function show(): string { return root.show() }
    function hide(): string { return root.hide() }
    function toggle(): string { return root.toggle() }
    function status(): string { root.refreshStatus(); return root.statusJson() }
    function debug(): string { root.refreshStatus(); return root.statusJson() }

    function screenshot(mode: string): string { return root.screenshot(mode || "selection") }
    function record(mode: string): string { return String(mode || "") === "" ? root.recordPicker() : root.record(mode) }

    function captureToFile(): string { return root.captureToFile() }
    function captureToClipboard(): string { return root.captureToClipboard() }

    function captureScreen(): string { return root.screenshot("screen") }
    function captureDisplay(): string { return root.screenshot("display") }
    function captureSelection(): string { return root.captureSelection() }
    function captureWindow(): string { return root.screenshot("window") }
    function captureActiveWindow(): string { return root.screenshot("active-window") }
    function captureLastSelection(): string { return root.screenshot("last") }

    function copyScreen(): string { return root.screenshot("screen", "clipboard") }
    function copySelection(): string { return root.copySelection() }
    function copyWindow(): string { return root.screenshot("window", "clipboard") }

    function recordScreen(): string { return root.record("screen") }
    function recordSelection(): string { return root.recordSelection() }
    function stopRecording(): string { return root.stopRecording() }
    function toggleRecording(): string { return root.toggleRecording() }
    function openLast(): string { return root.openLast() }

    function outputMode(value: string): string { return root.setOutputMode(value) }
    function saveLocation(value: string): string { return root.setSaveLocation(value) }
    function timer(value: string): string { return root.setTimer(value) }
    function cursor(value: string): string { return root.setIncludeCursor(value) }
    function desktopAudio(value: string): string { return root.setRecordDesktopAudio(value) }
    function microphoneAudio(value: string): string { return root.setRecordMicrophoneAudio(value) }
    function webcam(value: string): string { return root.setRecordWebcam(value) }
    function keystrokes(value: string): string { return root.setRecordKeystrokes(value) }
  }
}
