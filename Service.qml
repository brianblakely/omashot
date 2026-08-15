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
  readonly property string saveLocation: setting("saveLocation", "pictures")
  readonly property int timerSeconds: clampInt(setting("timerSeconds", 0), 0, 60)
  readonly property bool includeCursor: setting("includeCursor", false) === true
  readonly property bool recordDesktopAudio: setting("recordDesktopAudio", false) === true
  readonly property bool recordMicrophoneAudio: setting("recordMicrophoneAudio", false) === true
  readonly property bool recordWebcam: setting("recordWebcam", false) === true

  property bool recording: false
  property string lastStatus: "{}"
  property var pendingScreenshotArgs: null

  function clampInt(value, min, max) {
    var parsed = parseInt(value, 10)
    if (!isFinite(parsed)) parsed = min
    return Math.max(min, Math.min(max, parsed))
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

  function captureContext(geometry, screenName, outputOverride, freezePid) {
    var context = ({})
    var selectedGeometry = String(geometry || "").replace(/^\s+|\s+$/g, "")
    var selectedScreen = String(screenName || "")
    var selectedOutput = String(outputOverride || "")
    var pid = Math.floor(Number(freezePid))

    if (selectedGeometry !== "") context.geometry = selectedGeometry
    if (selectedScreen !== "") context.screenName = selectedScreen
    if (selectedOutput !== "") context.action = selectedOutput
    if (isFinite(pid) && pid > 0) context.freezePid = pid
    return JSON.stringify(context)
  }

  function runDetached(args) {
    if (!helperPath) return "missing-helper"
    Quickshell.execDetached(["bash", helperPath].concat(args))
    return "ok"
  }

  function runScreenshot(args, includeDemo) {
    if (includeDemo !== true) {
      hide()
      return runDetached(args)
    }

    if (!helperPath) return "missing-helper"
    if (demoScreenshotProc.running) return "busy"

    pendingScreenshotArgs = args.slice(0)
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
    return runScreenshot(["screenshot", target, captureContext("", "", outputOverride, freezePid)], includeDemo)
  }

  function screenshotGeometry(geometry, screenName, outputOverride, captureModeOverride, freezePid, includeDemo) {
    var selectedGeometry = String(geometry || "").replace(/^\s+|\s+$/g, "")
    if (selectedGeometry === "") return "missing-geometry"

    saveSettings({ captureMode: String(captureModeOverride || "selection") })
    return runScreenshot(["screenshot", "selection",
      captureContext(selectedGeometry, screenName, outputOverride, freezePid)], includeDemo)
  }

  function recordGeometry(geometry, screenName) {
    var selectedGeometry = String(geometry || "").replace(/^\s+|\s+$/g, "")
    if (selectedGeometry === "") return "missing-geometry"

    saveSettings({ captureMode: "record-selection" })
    hide()

    return runDetached(["record", "selection", captureContext(selectedGeometry, screenName, "", "")])
  }

  function record(mode) {
    var target = String(mode || "selection")
    saveSettings({ captureMode: target === "screen" ? "record-screen" : "record-selection" })
    hide()
    return runDetached(["record", target, captureContext("", "", "", "")])
  }

  function stopRecording() {
    hide()
    return runDetached(["stop-recording"])
  }

  function toggleRecording() {
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
    var next = String(value || "pictures")
    saveSettings({ saveLocation: next })
    return next
  }

  function setTimer(value) {
    var next = clampInt(value, 0, 60)
    saveSettings({ timerSeconds: next })
    return String(next)
  }

  function setIncludeCursor(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ includeCursor: next })
    return next ? "true" : "false"
  }

  function setRecordDesktopAudio(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ recordDesktopAudio: next })
    return next ? "true" : "false"
  }

  function setRecordMicrophoneAudio(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ recordMicrophoneAudio: next })
    return next ? "true" : "false"
  }

  function setRecordWebcam(value) {
    var next = value === true || String(value).toLowerCase() === "true"
    saveSettings({ recordWebcam: next })
    return next ? "true" : "false"
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Process {
    id: demoScreenshotProc

    onExited: function() {
      var args = root.pendingScreenshotArgs
      root.pendingScreenshotArgs = null
      root.hide()
      if (args && args.length > 0) root.runDetached(args)
    }
  }

  Process {
    id: statusProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastStatus = String(text || "{}").trim() || "{}"
        try {
          var parsed = JSON.parse(root.lastStatus)
          root.recording = parsed.recording === true
        } catch (e) {
          root.recording = false
        }
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
  }
}
