import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "b.omashot"
  property string captureKind: "screenshot"
  property bool hasSelection: false
  property int selectionX: 0
  property int selectionY: 0
  property int selectionW: 1
  property int selectionH: 1
  property string selectionScreenName: ""
  property string pointerAction: ""
  property int pointerStartX: 0
  property int pointerStartY: 0
  property int pointerSelectionX: 0
  property int pointerSelectionY: 0
  property int pointerSelectionW: 1
  property int pointerSelectionH: 1
  property int pointerAnchorX: 0
  property int pointerAnchorY: 0
  property bool pointerHadSelection: false
  property string pickerAction: ""
  property string targetKind: ""
  property bool regionLocked: false
  property bool regionOnlyPicker: false
  property bool freezeOpenPending: false
  property bool freezeCapturePending: false
  property var pickerClients: []
  property var pickerMonitors: []

  readonly property string screenRecordingIcon: "󰻂" // Omarchy bar recording indicator
  readonly property string recordingPlayIcon: "" // nf-fa-circle_play
  readonly property string recordingStopIcon: "" // nf-fa-circle_stop

  readonly property var captureKinds: [
    { value: "screenshot", label: "Screenshot", icon: "" },
    { value: "recording", label: "Screen Recording", icon: screenRecordingIcon }
  ]

  readonly property bool recordingMode: captureKind === "recording"
  readonly property bool recording: service && service.recording === true
  readonly property bool pickerMode: pickerAction !== ""
  readonly property bool targetDiscoveryMode: !regionOnlyPicker
  readonly property bool regionEditor: true
  readonly property bool hasCaptureTarget: targetKind === "screen"
    || ((targetKind === "window" || targetKind === "region") && hasSelection)
  readonly property bool canRunSelected: recording || hasCaptureTarget
  readonly property bool showSelectionFrame: hasSelection && targetKind === "region"
  readonly property int minimumSelectionSize: 1
  readonly property real pointerDragThreshold: Style.space(4)
  readonly property real topEdgeTargetHeight: Math.max(1, Style.space(4))
  readonly property real regionBorderWidth: Math.max(1, Style.normalBorderWidth)

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) { payload = ({}) }

    if (payload.action) {
      pickerAction = normalizePickerAction(payload.action)
      captureKind = pickerAction === "record" ? "recording" : "screenshot"
      hasSelection = false
      targetKind = ""
      regionLocked = false
      regionOnlyPicker = payload.regionOnly === true || String(payload.target || "") === "region"
      refreshPickerTargets()
    } else {
      pickerAction = ""
      regionOnlyPicker = false
      captureKind = "screenshot"
      clearSelection()
      refreshPickerTargets()
    }

    if (service && typeof service.refreshStatus === "function") service.refreshStatus()
    freezeAndShowOverlay()
  }

  function close() {
    var preserveFreeze = freezeCapturePending && freezeProc.running
    opened = false
    freezeOpenPending = false
    freezeCapturePending = false
    freezeOpenTimer.stop()
    if (preserveFreeze) freezeCaptureCleanupTimer.restart()
    else {
      freezeCaptureCleanupTimer.stop()
      if (freezeProc.running) freezeProc.running = false
    }
    pickerAction = ""
    targetKind = ""
    regionLocked = false
    regionOnlyPicker = false
    finishPointer()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function handleEscape() {
    if (recording && service && typeof service.stopRecording === "function") {
      service.stopRecording()
      return
    }

    dismiss()
  }

  function clearSelection() {
    hasSelection = false
    selectionScreenName = ""
    targetKind = ""
    regionLocked = false
    finishPointer()
  }

  function setCaptureKind(kind) {
    var nextKind = String(kind || "screenshot") === "recording" ? "recording" : "screenshot"
    if (captureKind === nextKind) {
      clearSelection()
      return
    }

    captureKind = nextKind
    if (service && typeof service.setCaptureMode === "function")
      service.setCaptureMode(nextKind === "recording" ? "record-screen" : "screen")
  }

  function freezePidForScreenshot() {
    if (!freezeProc.running || !service || Number(service.timerSeconds) > 0) return ""

    var pid = parseInt(String(freezeProc.processId || ""), 10)
    if (!isFinite(pid) || pid <= 0) return ""

    // The helper takes ownership of this process and stops it after grim has
    // copied the frozen surface. The cleanup timer is only a failure fallback.
    freezeCapturePending = true
    return String(pid)
  }

  function takeScreenshot(mode, outputOverride) {
    if (!service || typeof service.screenshot !== "function") return
    return service.screenshot(mode, outputOverride || "", freezePidForScreenshot())
  }

  function takeGeometryScreenshot(geometry, screenName, outputOverride, captureModeOverride) {
    if (!service || typeof service.screenshotGeometry !== "function") return
    return service.screenshotGeometry(geometry, screenName, outputOverride || "", captureModeOverride || "",
      freezePidForScreenshot())
  }

  function runSelected(screenName) {
    if (!service) return

    if (recording) {
      service.stopRecording()
      return
    }

    captureCurrentTarget(screenName)
  }

  function toggleBoolean(name) {
    if (!service) return
    if (name === "cursor") service.setIncludeCursor(!service.includeCursor)
    else if (name === "desktopAudio") service.setRecordDesktopAudio(!service.recordDesktopAudio)
    else if (name === "microphoneAudio") service.setRecordMicrophoneAudio(!service.recordMicrophoneAudio)
    else if (name === "webcam") service.setRecordWebcam(!service.recordWebcam)
  }

  function normalizePickerAction(action) {
    var value = String(action || "file").toLowerCase()
    if (value === "clipboard" || value === "copy") return "clipboard"
    if (value === "record" || value === "recording") return "record"
    return "file"
  }

  function showOverlay() {
    freezeOpenPending = false
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function freezeAndShowOverlay() {
    opened = false
    freezeOpenPending = true
    freezeCapturePending = false
    freezeCaptureCleanupTimer.stop()
    if (freezeProc.running) freezeProc.running = false
    freezeProc.running = true
    freezeOpenTimer.restart()
  }

  function refreshPickerTargets() {
    if (!targetDiscoveryMode || pickerTargetsProc.running) return
    pickerTargetsProc.running = true
  }

  function panelScreenName(panel) {
    return panel && panel.screen && panel.screen.name ? String(panel.screen.name) : ""
  }

  function isPointAtTopEdge(y) {
    return y <= topEdgeTargetHeight
  }

  function monitorForScreen(screenName) {
    var name = String(screenName || "")
    var fallback = null
    for (var i = 0; i < pickerMonitors.length; i++) {
      var monitor = pickerMonitors[i]
      if (!monitor) continue
      if (name !== "" && String(monitor.name || "") === name) return monitor
      if (monitor.focused === true) fallback = monitor
    }
    return fallback
  }

  function monitorOffset(screenName) {
    var monitor = monitorForScreen(screenName)
    return {
      x: monitor ? Math.round(Number(monitor.x) || 0) : 0,
      y: monitor ? Math.round(Number(monitor.y) || 0) : 0
    }
  }

  function monitorWorkspaceId(screenName) {
    var monitor = monitorForScreen(screenName)
    return monitor && monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : NaN
  }

  function localToGlobal(x, y, screenName) {
    var offset = monitorOffset(screenName)
    return { x: Math.round(x + offset.x), y: Math.round(y + offset.y) }
  }

  function globalRectToLocal(rect, screenName, maxWidth, maxHeight) {
    var offset = monitorOffset(screenName)
    var x = Math.round(Number(rect.x) || 0) - offset.x
    var y = Math.round(Number(rect.y) || 0) - offset.y
    var width = Math.round(Number(rect.width) || 0)
    var height = Math.round(Number(rect.height) || 0)
    var left = clamp(x, 0, maxWidth)
    var top = clamp(y, 0, maxHeight)
    var right = clamp(x + width, 0, maxWidth)
    var bottom = clamp(y + height, 0, maxHeight)
    return { x: left, y: top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) }
  }

  function clientRect(client) {
    if (!client || !client.at || !client.size) return null
    return {
      x: Math.round(Number(client.at[0]) || 0),
      y: Math.round(Number(client.at[1]) || 0),
      width: Math.round(Number(client.size[0]) || 0),
      height: Math.round(Number(client.size[1]) || 0)
    }
  }

  function clientAt(x, y, maxWidth, maxHeight, screenName) {
    var point = localToGlobal(x, y, screenName)
    var workspaceId = monitorWorkspaceId(screenName)

    for (var i = pickerClients.length - 1; i >= 0; i--) {
      var client = pickerClients[i]
      if (!client || client.mapped === false || client.hidden === true || client.minimized === true) continue
      if (client.workspace && isFinite(workspaceId) && Number(client.workspace.id) !== workspaceId) continue

      var rect = clientRect(client)
      if (!rect || rect.width <= 0 || rect.height <= 0) continue
      if (point.x >= rect.x && point.x < rect.x + rect.width && point.y >= rect.y && point.y < rect.y + rect.height)
        return client
    }

    return null
  }

  function setTargetFromClient(client, maxWidth, maxHeight, screenName) {
    var rect = clientRect(client)
    if (!rect) return false
    var local = globalRectToLocal(rect, screenName, maxWidth, maxHeight)
    setSelection(local.x, local.y, local.width, local.height, maxWidth, maxHeight)
    selectionScreenName = String(screenName || "")
    targetKind = "window"
    regionLocked = false
    return true
  }

  function setScreenTarget(maxWidth, maxHeight, screenName) {
    selectionScreenName = String(screenName || "")
    setSelection(0, 0, maxWidth, maxHeight, maxWidth, maxHeight)
    targetKind = "screen"
    regionLocked = false
  }

  function updateTargetHover(x, y, maxWidth, maxHeight, screenName) {
    if (!targetDiscoveryMode || pointerAction !== "") return
    if (regionOnlyPicker) return

    if (targetKind === "region" && hasSelection) {
      regionLocked = true
      return
    }

    if (isPointAtTopEdge(y)) {
      setScreenTarget(maxWidth, maxHeight, screenName)
      return
    }

    var client = clientAt(x, y, maxWidth, maxHeight, screenName)
    if (client && setTargetFromClient(client, maxWidth, maxHeight, screenName)) return

    targetKind = ""
    hasSelection = false
  }

  function clamp(value, min, max) {
    value = Math.round(Number(value) || 0)
    min = Math.round(Number(min) || 0)
    max = Math.round(Number(max) || 0)
    if (max < min) max = min
    return Math.max(min, Math.min(max, value))
  }

  function setSelection(x, y, width, height, maxWidth, maxHeight) {
    var maxW = Math.max(minimumSelectionSize, Math.round(Number(maxWidth) || 1))
    var maxH = Math.max(minimumSelectionSize, Math.round(Number(maxHeight) || 1))
    var nextW = clamp(width, minimumSelectionSize, maxW)
    var nextH = clamp(height, minimumSelectionSize, maxH)

    selectionX = clamp(x, 0, maxW - nextW)
    selectionY = clamp(y, 0, maxH - nextH)
    selectionW = nextW
    selectionH = nextH
    hasSelection = true
  }

  function setSelectionEdges(left, top, right, bottom, maxWidth, maxHeight, activeEdge) {
    var maxW = Math.max(minimumSelectionSize, Math.round(Number(maxWidth) || 1))
    var maxH = Math.max(minimumSelectionSize, Math.round(Number(maxHeight) || 1))
    var l = clamp(left, 0, maxW - minimumSelectionSize)
    var t = clamp(top, 0, maxH - minimumSelectionSize)
    var r = clamp(right, minimumSelectionSize, maxW)
    var b = clamp(bottom, minimumSelectionSize, maxH)

    if (r - l < minimumSelectionSize) {
      if (String(activeEdge || "").indexOf("w") >= 0) l = Math.max(0, r - minimumSelectionSize)
      else r = Math.min(maxW, l + minimumSelectionSize)
    }
    if (b - t < minimumSelectionSize) {
      if (String(activeEdge || "").indexOf("n") >= 0) t = Math.max(0, b - minimumSelectionSize)
      else b = Math.min(maxH, t + minimumSelectionSize)
    }

    setSelection(l, t, r - l, b - t, maxW, maxH)
  }

  function ensureSelection(maxWidth, maxHeight, screenName) {
    if (screenName !== undefined) selectionScreenName = String(screenName || "")
    if (hasSelection) {
      setSelection(selectionX, selectionY, selectionW, selectionH, maxWidth, maxHeight)
      return
    }

    var maxW = Math.max(minimumSelectionSize, Math.round(Number(maxWidth) || 1))
    var maxH = Math.max(minimumSelectionSize, Math.round(Number(maxHeight) || 1))
    var nextW = Math.max(minimumSelectionSize, Math.round(maxW * 0.5))
    var nextH = Math.max(minimumSelectionSize, Math.round(maxH * 0.5))
    setSelection(Math.round((maxW - nextW) / 2), Math.round((maxH - nextH) / 2), nextW, nextH, maxW, maxH)
  }

  function selectionGeometry() {
    if (!hasSelection) return ""
    return Math.round(selectionX) + "," + Math.round(selectionY) + " " + Math.round(selectionW) + "x" + Math.round(selectionH)
  }

  function beginPointer(action, x, y, maxWidth, maxHeight, screenName) {
    selectionScreenName = String(screenName || "")
    pointerHadSelection = hasSelection
    pointerAction = String(action || "")
    pointerStartX = clamp(x, 0, maxWidth)
    pointerStartY = clamp(y, 0, maxHeight)
    pointerSelectionX = selectionX
    pointerSelectionY = selectionY
    pointerSelectionW = selectionW
    pointerSelectionH = selectionH
    pointerAnchorX = pointerStartX
    pointerAnchorY = pointerStartY

    if (pointerAction === "draw")
      setSelection(pointerStartX, pointerStartY, minimumSelectionSize, minimumSelectionSize, maxWidth, maxHeight)
    else if (pointerAction !== "region-draw-pending" && pointerAction !== "region-move-pending")
      ensureSelection(maxWidth, maxHeight, screenName)
  }

  function beginRegionPointer(action, x, y, maxWidth, maxHeight, screenName) {
    var pendingAction = String(action || "draw") === "move" ? "region-move-pending" : "region-draw-pending"
    beginPointer(pendingAction, x, y, maxWidth, maxHeight, screenName)
  }

  function beginTargetPointer(x, y, maxWidth, maxHeight, screenName) {
    selectionScreenName = String(screenName || "")

    if (regionOnlyPicker || (targetKind === "region" && hasSelection)) {
      targetKind = "region"
      regionLocked = true
      beginRegionPointer("draw", x, y, maxWidth, maxHeight, screenName)
      return
    }

    pointerAction = "pending"
    pointerStartX = clamp(x, 0, maxWidth)
    pointerStartY = clamp(y, 0, maxHeight)
    pointerAnchorX = pointerStartX
    pointerAnchorY = pointerStartY
    pointerSelectionX = selectionX
    pointerSelectionY = selectionY
    pointerSelectionW = selectionW
    pointerSelectionH = selectionH
    regionLocked = false

    if (isPointAtTopEdge(pointerStartY)) {
      setScreenTarget(maxWidth, maxHeight, screenName)
      return
    }

    var client = clientAt(pointerStartX, pointerStartY, maxWidth, maxHeight, screenName)
    if (client && setTargetFromClient(client, maxWidth, maxHeight, screenName)) return

    targetKind = ""
    hasSelection = false
  }

  function updatePointer(x, y, maxWidth, maxHeight) {
    if (pointerAction === "") return

    var px = clamp(x, 0, maxWidth)
    var py = clamp(y, 0, maxHeight)
    var dx = px - pointerStartX
    var dy = py - pointerStartY

    if (pointerAction === "region-draw-pending" || pointerAction === "region-move-pending") {
      if (Math.abs(dx) + Math.abs(dy) < pointerDragThreshold) return

      if (pointerAction === "region-draw-pending") {
        pointerAction = "draw"
        setSelection(pointerStartX, pointerStartY, minimumSelectionSize, minimumSelectionSize, maxWidth, maxHeight)
      } else {
        pointerAction = "move"
      }
    }

    if (pointerAction === "pending") {
      if (Math.abs(dx) + Math.abs(dy) < pointerDragThreshold) return
      pointerAction = "draw"
      targetKind = "region"
      regionLocked = true
      setSelection(pointerStartX, pointerStartY, minimumSelectionSize, minimumSelectionSize, maxWidth, maxHeight)
    }

    if (pointerAction === "draw") {
      setSelectionEdges(Math.min(pointerAnchorX, px), Math.min(pointerAnchorY, py),
        Math.max(pointerAnchorX, px), Math.max(pointerAnchorY, py), maxWidth, maxHeight, "se")
      return
    }

    if (pointerAction === "move") {
      setSelection(pointerSelectionX + dx, pointerSelectionY + dy, pointerSelectionW, pointerSelectionH, maxWidth, maxHeight)
      return
    }

    var left = pointerSelectionX
    var top = pointerSelectionY
    var right = pointerSelectionX + pointerSelectionW
    var bottom = pointerSelectionY + pointerSelectionH

    if (pointerAction.indexOf("w") >= 0) left += dx
    if (pointerAction.indexOf("e") >= 0) right += dx
    if (pointerAction.indexOf("n") >= 0) top += dy
    if (pointerAction.indexOf("s") >= 0) bottom += dy

    setSelectionEdges(left, top, right, bottom, maxWidth, maxHeight, pointerAction)
  }

  function finishPointer() {
    pointerAction = ""
    pointerHadSelection = false
  }

  function finishRegionPointer(maxWidth, maxHeight) {
    var action = pointerAction
    var placeExisting = pointerHadSelection
      && (action === "region-draw-pending" || action === "region-move-pending")
    var x = pointerStartX
    var y = pointerStartY
    var width = pointerSelectionW
    var height = pointerSelectionH

    finishPointer()
    if (placeExisting) setSelection(x, y, width, height, maxWidth, maxHeight)
  }

  function finishTargetPointer(maxWidth, maxHeight, screenName) {
    var action = pointerAction

    if (action === "region-draw-pending" || action === "region-move-pending") {
      finishRegionPointer(maxWidth, maxHeight)
      if (hasSelection) {
        targetKind = "region"
        regionLocked = true
      }
      return
    }

    finishPointer()

    if (action === "draw") {
      if (hasSelection) {
        targetKind = "region"
        regionLocked = true
      }
      return
    }

    if (action === "pending") {
      if (targetKind === "screen" || targetKind === "window") captureCurrentTarget(screenName)
    }
  }

  function keyDirection(key) {
    if (key === Qt.Key_Left || key === Qt.Key_H) return "left"
    if (key === Qt.Key_Right || key === Qt.Key_L) return "right"
    if (key === Qt.Key_Up || key === Qt.Key_K) return "up"
    if (key === Qt.Key_Down || key === Qt.Key_J) return "down"
    return ""
  }

  function moveSelection(direction, increment, maxWidth, maxHeight) {
    var dx = direction === "left" ? -increment : (direction === "right" ? increment : 0)
    var dy = direction === "up" ? -increment : (direction === "down" ? increment : 0)
    setSelection(selectionX + dx, selectionY + dy, selectionW, selectionH, maxWidth, maxHeight)
  }

  function resizeSelectionByKey(direction, grow, increment, maxWidth, maxHeight) {
    if (!grow) {
      if (direction === "left") direction = "right"
      else if (direction === "right") direction = "left"
      else if (direction === "up") direction = "down"
      else if (direction === "down") direction = "up"
    }

    var left = selectionX
    var top = selectionY
    var right = selectionX + selectionW
    var bottom = selectionY + selectionH
    var edge = ""

    if (direction === "left") {
      left += grow ? -increment : increment
      edge = "w"
    } else if (direction === "right") {
      right += grow ? increment : -increment
      edge = "e"
    } else if (direction === "up") {
      top += grow ? -increment : increment
      edge = "n"
    } else if (direction === "down") {
      bottom += grow ? increment : -increment
      edge = "s"
    }

    setSelectionEdges(left, top, right, bottom, maxWidth, maxHeight, edge)
  }

  function handleSelectionKey(event, maxWidth, maxHeight, screenName) {
    var direction = keyDirection(event.key)
    if (direction === "" || targetKind !== "region" || !hasSelection) return false

    ensureSelection(maxWidth, maxHeight, screenName)
    targetKind = "region"
    regionLocked = true
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var increment = (event.modifiers & Qt.AltModifier) !== 0 ? 10 : 1
    if (shift) resizeSelectionByKey(direction, !ctrl, increment, maxWidth, maxHeight)
    else moveSelection(direction, increment, maxWidth, maxHeight)
    return true
  }

  function captureScreenTarget(screenName) {
    if (!service) return
    if (pickerMode) {
      if (pickerAction === "record") service.record("screen")
      else takeScreenshot("screen", pickerAction === "clipboard" ? "clipboard" : "file")
    } else if (recordingMode) service.record("screen")
    else takeScreenshot("screen")
  }

  function captureWholeScreen() {
    if (!service) return

    if (pickerMode && pickerAction !== "record") {
      takeScreenshot("screen", pickerAction === "clipboard" ? "clipboard" : "file")
      return
    }

    takeScreenshot("screen")
  }

  function captureCurrentTarget(screenName) {
    if (!service || !hasCaptureTarget) return

    if (targetKind === "screen") {
      captureScreenTarget(screenName)
      return
    }

    if ((targetKind === "window" || targetKind === "region") && hasSelection) {
      var geometry = selectionGeometry()
      var targetScreen = screenName || selectionScreenName || ""
      if (pickerMode) {
        if (pickerAction === "record" && typeof service.recordGeometry === "function")
          service.recordGeometry(geometry, targetScreen)
        else if (typeof service.screenshotGeometry === "function")
          takeGeometryScreenshot(geometry, targetScreen, pickerAction === "clipboard" ? "clipboard" : "file")
      } else if (recordingMode && typeof service.recordGeometry === "function") {
        service.recordGeometry(geometry, targetScreen)
      } else if (typeof service.screenshotGeometry === "function") {
        takeGeometryScreenshot(geometry, targetScreen, "", targetKind === "window" ? "window" : "selection")
      }
    }
  }

  function captureSelectedTarget(screenName) {
    if (hasCaptureTarget) captureCurrentTarget(screenName)
  }

  component MenuButton: Rectangle {
    id: menuButton

    property string iconText: ""
    property string tooltipText: ""
    property bool checked: false
    property bool cta: false

    signal clicked()

    readonly property color activeText: Color.menu.selectedText
    readonly property color idleText: Color.menu.text
    readonly property color ctaColor: Color.accent
    readonly property color selectedBorder: Color.menu.selectedBorder.a > 0
      ? Color.menu.selectedBorder
      : Style.selectedBorderFor(idleText, activeText)

    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight
    implicitWidth: Style.spacing.controlHeight
    implicitHeight: Style.spacing.controlHeight
    radius: Style.cornerRadius
    color: cta && buttonMouse.pressed ? Util.alpha(ctaColor, 0.36)
      : cta && buttonMouse.containsMouse ? Util.alpha(ctaColor, 0.30)
      : cta ? Util.alpha(ctaColor, 0.22)
      : buttonMouse.pressed ? Style.pressedFillFor(idleText, activeText)
      : buttonMouse.containsMouse ? Style.hoverFillFor(idleText, activeText)
      : checked ? Color.menu.selectedBackground
      : Style.normalFillFor(idleText, activeText)
    border.color: cta ? Util.alpha(ctaColor, buttonMouse.containsMouse ? 1.0 : 0.78)
      : checked ? selectedBorder
      : buttonMouse.containsMouse ? Style.hoverBorderFor(idleText, activeText)
      : Style.normalBorderFor(idleText, activeText)
    border.width: cta ? Math.max(1, Style.normalBorderWidth)
      : checked ? Math.max(1, Style.selectedBorderWidth, Style.normalBorderWidth)
      : Style.normalBorderWidth

    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
      anchors.centerIn: parent
      text: menuButton.iconText
      color: menuButton.cta ? menuButton.idleText : (menuButton.checked ? menuButton.activeText : menuButton.idleText)
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.icon
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: menuButton.clicked()
    }

    PanelToolTip {
      visible: menuButton.tooltipText !== "" && buttonMouse.containsMouse
      delay: 0
      text: menuButton.tooltipText
      fontFamily: Style.font.menuFamily
    }
  }

  component IconDropdown: Rectangle {
    id: iconDropdown

    property string label: ""
    property string iconText: ""
    property string value: ""
    property var options: []
    property int popupWidth: Style.space(160)

    signal changed(string value)

    function optionValue(o) {
      return (o && typeof o === "object") ? String(o.value) : String(o)
    }

    function optionLabel(o) {
      return (o && typeof o === "object") ? String(o.label) : String(o)
    }

    function currentLabel() {
      for (var i = 0; i < options.length; i++) {
        if (optionValue(options[i]) === value) return optionLabel(options[i])
      }
      return value
    }

    width: Style.spacing.controlHeight
    height: Style.spacing.controlHeight
    implicitWidth: dropdownRow.implicitWidth + Style.spacing.controlPaddingX
    implicitHeight: Style.spacing.controlHeight
    radius: Style.cornerRadius
    color: dropdownMouse.pressed ? Style.pressedFillFor(Color.menu.text, Color.menu.selectedText)
      : dropdownMouse.containsMouse || popup.opened ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText)
      : Style.normalFillFor(Color.menu.text, Color.menu.selectedText)
    border.color: dropdownMouse.containsMouse || popup.opened
      ? Style.hoverBorderFor(Color.menu.text, Color.menu.selectedText)
      : Style.normalBorderFor(Color.menu.text, Color.menu.selectedText)
    border.width: dropdownMouse.containsMouse || popup.opened ? Style.hoverBorderWidth : Style.normalBorderWidth

    Behavior on color { ColorAnimation { duration: 100 } }

    function positionPopup() {
      var boundary = iconDropdown.Window.window ? iconDropdown.Window.window.contentItem : iconDropdown
      if (!boundary) return

      var gap = Style.spacing.xxs
      var position = iconDropdown.mapToItem(boundary, 0, 0)
      var popupHeight = popup.height > 0 ? popup.height : popup.implicitHeight
      var availableWidth = boundary.width
      var availableHeight = boundary.height
      var belowY = position.y + iconDropdown.height + gap
      var aboveY = position.y - popupHeight - gap
      var preferredX = position.x
      var preferredY = belowY

      if (preferredX + popup.width > availableWidth)
        preferredX = position.x + iconDropdown.width - popup.width
      if (belowY + popupHeight > availableHeight)
        preferredY = aboveY

      popup.x = Math.max(0, Math.min(availableWidth - popup.width, preferredX)) - position.x
      popup.y = Math.max(0, Math.min(availableHeight - popupHeight, preferredY)) - position.y
    }

    Row {
      id: dropdownRow
      anchors.centerIn: parent
      spacing: Style.spacing.xxs

      Text {
        text: iconDropdown.iconText
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.icon
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: "󰅀"
        color: Qt.darker(Color.menu.text, 1.25)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: dropdownMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: popup.visible ? popup.close() : popup.open()
    }

    PanelToolTip {
      visible: !popup.opened && dropdownMouse.containsMouse
      delay: 0
      text: iconDropdown.label + ": " + iconDropdown.currentLabel()
      fontFamily: Style.font.menuFamily
    }

    Controls.Popup {
      id: popup
      parent: iconDropdown
      x: 0
      y: 0
      width: Math.min(iconDropdown.popupWidth,
                      iconDropdown.Window.window && iconDropdown.Window.window.contentItem.width > 0
                        ? iconDropdown.Window.window.contentItem.width
                        : iconDropdown.popupWidth)
      implicitHeight: Math.min(iconDropdown.options.length * Style.spacing.popupRowHeight + Math.max(0, iconDropdown.options.length - 1) * Style.spacing.labelGap + Style.spacing.xxs,
                               Style.spacing.popupRowHeight * 8 + 7 * Style.spacing.labelGap + Style.spacing.xxs)
      padding: Style.spacing.hairline
      focus: true
      closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent

      onAboutToShow: iconDropdown.positionPopup()
      background: Rectangle {
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: Style.normalBorderWidth
        radius: Style.cornerRadius
      }

      onOpened: {
        iconDropdown.positionPopup()
        optionList.currentIndex = Math.max(0, optionList.indexOfValue(iconDropdown.value))
        optionList.forceActiveFocus()
        Qt.callLater(function() { iconDropdown.positionPopup() })
      }

      contentItem: ListView {
        id: optionList
        spacing: Style.spacing.labelGap
        implicitHeight: contentHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: iconDropdown.options
        currentIndex: -1

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.recording) root.handleEscape()
            else popup.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.text === "j") {
            optionList.currentIndex = Math.min(iconDropdown.options.length - 1, optionList.currentIndex + 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            optionList.currentIndex = Math.max(0, optionList.currentIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            optionList.selectCurrent()
            event.accepted = true
          }
        }

        function indexOfValue(v) {
          for (var i = 0; i < iconDropdown.options.length; i++) {
            if (iconDropdown.optionValue(iconDropdown.options[i]) === v) return i
          }
          return -1
        }

        function selectCurrent() {
          if (currentIndex < 0 || currentIndex >= iconDropdown.options.length) return
          var next = iconDropdown.optionValue(iconDropdown.options[currentIndex])
          iconDropdown.changed(next)
          if (iconDropdown.value !== next) iconDropdown.value = next
          popup.close()
        }

        delegate: Rectangle {
          required property var modelData
          required property int index

          width: optionList.width
          height: Style.spacing.popupRowHeight
          color: index === optionList.currentIndex
            ? Style.hoverFillFor(Color.menu.text, Color.menu.selectedText)
            : "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.controlPaddingX
            anchors.rightMargin: Style.spacing.controlPaddingX
            text: iconDropdown.optionLabel(modelData)
            color: index === optionList.currentIndex ? Style.hoverStateColor(Color.menu.text, Color.menu.selectedText) : Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: optionList.currentIndex = parent.index
            onClicked: optionList.selectCurrent()
          }
        }
      }
    }
  }

  component GroupGap: Item {
    width: Style.spacing.xs
    height: Style.spacing.controlHeight
  }

  Process {
    id: pickerTargetsProc
    command: [
      "bash",
      "-c",
      "printf '{\"monitors\":'; hyprctl monitors -j 2>/dev/null || printf '[]'; printf ',\"clients\":'; hyprctl clients -j 2>/dev/null || printf '[]'; printf '}'"
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.pickerMonitors = Array.isArray(parsed.monitors) ? parsed.monitors : []
          root.pickerClients = Array.isArray(parsed.clients) ? parsed.clients : []

          if (root.opened && root.targetDiscoveryMode) Qt.callLater(function() {
            if (!root.opened || !root.targetDiscoveryMode || !selectionPointer.containsMouse) return
            root.updateTargetHover(selectionPointer.mouseX, selectionPointer.mouseY,
              panel.width, panel.height, panel.currentScreenName)
          })
        } catch (e) {
          root.pickerMonitors = []
          root.pickerClients = []
          if (root.targetKind === "window") root.clearSelection()
        }
      }
    }
  }

  Process {
    id: freezeProc
    command: ["hyprpicker", "-r", "-z", "-q"]
  }

  Timer {
    id: freezeCaptureCleanupTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (freezeProc.running) freezeProc.running = false
    }
  }

  Timer {
    id: freezeOpenTimer
    interval: 100
    repeat: false
    onTriggered: {
      if (root.freezeOpenPending) root.showOverlay()
    }
  }

  Timer {
    interval: 700
    running: root.opened && root.targetDiscoveryMode
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshPickerTargets()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "b-omashot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    readonly property string currentScreenName: root.panelScreenName(panel)

    onVisibleChanged: {
      if (visible && root.targetDiscoveryMode) root.refreshPickerTargets()
    }
    onWidthChanged: if (root.regionEditor && root.hasSelection) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)
    onHeightChanged: if (root.regionEditor && root.hasSelection) root.ensureSelection(panel.width, panel.height, panel.currentScreenName)

    component ResizeHandle: Rectangle {
      required property string edge
      property int cursor: Qt.ArrowCursor
      readonly property bool onLeft: edge.indexOf("w") >= 0
      readonly property bool onRight: edge.indexOf("e") >= 0
      readonly property bool onTop: edge.indexOf("n") >= 0
      readonly property bool onBottom: edge.indexOf("s") >= 0

      width: Math.max(10, Style.space(10))
      height: width
      x: onLeft ? -width + root.regionBorderWidth
        : onRight ? parent.width - root.regionBorderWidth
        : parent.width / 2 - width / 2
      y: onTop ? -height + root.regionBorderWidth
        : onBottom ? parent.height - root.regionBorderWidth
        : parent.height / 2 - height / 2
      radius: 0
      color: Color.menu.background
      border.color: Color.accent
      border.width: root.regionBorderWidth
      z: 2

      MouseArea {
        anchors.fill: parent
        enabled: root.pointerAction === ""
        hoverEnabled: true
        cursorShape: parent.cursor
        acceptedButtons: Qt.LeftButton
        onPressed: function(mouse) {
          var point = mapToItem(selectionLayer, mouse.x, mouse.y)
          keyCatcher.forceActiveFocus()
          root.targetKind = "region"
          root.regionLocked = true
          root.beginPointer(parent.edge, point.x, point.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
          mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
          var point = mapToItem(selectionLayer, mouse.x, mouse.y)
          root.updatePointer(point.x, point.y, selectionLayer.width, selectionLayer.height)
        }
        onReleased: root.finishPointer()
      }
    }

    Item {
      id: selectionLayer
      anchors.fill: parent
      visible: root.regionEditor

      Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim
        opacity: 0.72
        visible: !root.hasSelection
      }

      Rectangle {
        x: 0
        y: 0
        width: parent.width
        height: root.hasSelection ? root.selectionY : parent.height
        color: Color.menu.scrim
        opacity: 0.72
        visible: root.hasSelection
      }

      Rectangle {
        x: 0
        y: root.selectionY
        width: root.selectionX
        height: root.selectionH
        color: Color.menu.scrim
        opacity: 0.72
        visible: root.hasSelection
      }

      Rectangle {
        x: root.selectionX + root.selectionW
        y: root.selectionY
        width: Math.max(0, parent.width - x)
        height: root.selectionH
        color: Color.menu.scrim
        opacity: 0.72
        visible: root.hasSelection
      }

      Rectangle {
        x: 0
        y: root.selectionY + root.selectionH
        width: parent.width
        height: Math.max(0, parent.height - y)
        color: Color.menu.scrim
        opacity: 0.72
        visible: root.hasSelection
      }

      MouseArea {
        id: selectionPointer
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        acceptedButtons: Qt.LeftButton
        hoverEnabled: root.targetDiscoveryMode
        preventStealing: true
        onPressed: function(mouse) {
          keyCatcher.forceActiveFocus()
          root.beginTargetPointer(mouse.x, mouse.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
          mouse.accepted = true
        }
        onPositionChanged: function(mouse) {
          if (root.pointerAction !== "") root.updatePointer(mouse.x, mouse.y, selectionLayer.width, selectionLayer.height)
          else root.updateTargetHover(mouse.x, mouse.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
        }
        onReleased: root.finishTargetPointer(selectionLayer.width, selectionLayer.height, panel.currentScreenName)
        onCanceled: {
          root.finishPointer()
        }
      }

      Rectangle {
        x: root.selectionX
        y: root.selectionY
        width: root.selectionW
        height: root.selectionH
        visible: root.hasSelection && root.targetKind === "window"
        color: "transparent"
        border.color: Color.accent
        border.width: root.regionBorderWidth
      }

      Rectangle {
        id: selectionBox
        x: root.selectionX
        y: root.selectionY
        width: root.selectionW
        height: root.selectionH
        visible: root.showSelectionFrame
        color: "transparent"
        border.color: Color.accent
        border.width: root.regionBorderWidth

        MouseArea {
          anchors.fill: parent
          enabled: root.pointerAction === ""
          cursorShape: Qt.SizeAllCursor
          acceptedButtons: Qt.LeftButton
          preventStealing: true
          onPressed: function(mouse) {
            var point = mapToItem(selectionLayer, mouse.x, mouse.y)
            keyCatcher.forceActiveFocus()
            root.targetKind = "region"
            root.regionLocked = true
            root.beginRegionPointer("move", point.x, point.y, selectionLayer.width, selectionLayer.height, panel.currentScreenName)
            mouse.accepted = true
          }
          onPositionChanged: function(mouse) {
            var point = mapToItem(selectionLayer, mouse.x, mouse.y)
            root.updatePointer(point.x, point.y, selectionLayer.width, selectionLayer.height)
          }
          onReleased: root.finishRegionPointer(selectionLayer.width, selectionLayer.height)
        }

        ResizeHandle {
          edge: "nw"
          cursor: Qt.SizeFDiagCursor
        }

        ResizeHandle {
          edge: "n"
          cursor: Qt.SizeVerCursor
        }

        ResizeHandle {
          edge: "ne"
          cursor: Qt.SizeBDiagCursor
        }

        ResizeHandle {
          edge: "e"
          cursor: Qt.SizeHorCursor
        }

        ResizeHandle {
          edge: "se"
          cursor: Qt.SizeFDiagCursor
        }

        ResizeHandle {
          edge: "s"
          cursor: Qt.SizeVerCursor
        }

        ResizeHandle {
          edge: "sw"
          cursor: Qt.SizeBDiagCursor
        }

        ResizeHandle {
          edge: "w"
          cursor: Qt.SizeHorCursor
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.handleEscape()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.captureSelectedTarget(panel.currentScreenName)
          event.accepted = true
        } else if (root.regionEditor && root.handleSelectionKey(event, panel.width, panel.height, panel.currentScreenName)) {
          event.accepted = true
        }
      }
    }

    Shortcut {
      sequence: "Space"
      context: Qt.WindowShortcut
      autoRepeat: false
      onActivated: root.captureWholeScreen()
    }

    BorderSurface {
      id: toolbar
      visible: !root.pickerMode
      readonly property int dropdownButtonWidth: Style.spacing.controlHeight + Style.spacing.controlPaddingX
      readonly property real edgeMargin: Math.max(Style.gapsOut, Style.space(14))
      readonly property real normalX: (panel.width - toolbar.width) / 2
      readonly property real normalBottomY: panel.height - toolbar.height - toolbar.edgeMargin
      readonly property bool moveToTop: root.hasSelection && root.targetKind === "region" && !root.pickerMode
        && root.selectionX < toolbar.normalX + toolbar.width
        && root.selectionX + root.selectionW > toolbar.normalX
        && root.selectionY < toolbar.normalBottomY + toolbar.height
        && root.selectionY + root.selectionH > toolbar.normalBottomY
      readonly property real naturalContentWidth: {
        var items = content.visibleChildren
        var total = 0
        for (var i = 0; i < items.length; i++) total += items[i].width
        return total + Math.max(0, items.length - 1) * content.spacing
      }
      implicitWidth: naturalContentWidth + contentLeftInset + contentRightInset
      width: Math.max(1, Math.min(panel.width - Style.gapsOut * 2, implicitWidth))
      height: content.implicitHeight + padding * 2 + borderTop + borderBottom
      anchors.horizontalCenter: parent.horizontalCenter
      y: toolbar.moveToTop ? toolbar.edgeMargin : toolbar.normalBottomY
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.normalBorderWidth))
      padding: Style.spacing.xxl
      clip: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      Flow {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: toolbar.contentLeftInset
        anchors.rightMargin: toolbar.contentRightInset
        anchors.topMargin: toolbar.contentTopInset
        spacing: Style.spacing.xs

        Row {
          id: captureKindButtons
          height: Style.spacing.controlHeight
          spacing: Style.spacing.md

          Repeater {
            model: root.captureKinds

            Button {
              required property var modelData
              height: captureKindButtons.height
              text: String(modelData.label || "")
              iconText: String(modelData.icon || "")
              selected: root.captureKind === String(modelData.value || "")
              bordered: true
              foreground: Color.menu.text
              background: Color.menu.background
              accent: Color.accent
              fontFamily: Style.font.menuFamily
              fontSize: Style.font.bodySmall
              focusable: false
              onClicked: root.setCaptureKind(modelData.value)
            }
          }
        }

        GroupGap {}

        IconDropdown {
          label: "Save"
          iconText: "󰈙"
          visible: !root.recordingMode
          width: toolbar.dropdownButtonWidth
          popupWidth: Style.space(170)
          value: service ? service.outputMode : "file-and-clipboard"
          options: [
            { value: "file-and-clipboard", label: "File + Clipboard" },
            { value: "file", label: "File" },
            { value: "clipboard", label: "Clipboard" },
            { value: "editor", label: "Editor" }
          ]
          onChanged: function(value) { if (service) service.setOutputMode(value) }
        }

        IconDropdown {
          label: "Location"
          iconText: "󰉋"
          width: toolbar.dropdownButtonWidth
          popupWidth: Style.space(150)
          value: service
            ? (root.recordingMode && service.saveLocation === "pictures" ? "videos" : service.saveLocation)
            : (root.recordingMode ? "videos" : "pictures")
          options: root.recordingMode ? [
            { value: "videos", label: "Videos" },
            { value: "desktop", label: "Desktop" },
            { value: "documents", label: "Documents" },
            { value: "downloads", label: "Downloads" }
          ] : [
            { value: "pictures", label: "Pictures" },
            { value: "desktop", label: "Desktop" },
            { value: "documents", label: "Documents" },
            { value: "downloads", label: "Downloads" }
          ]
          onChanged: function(value) {
            if (service) service.setSaveLocation(root.recordingMode && value === "videos" ? "pictures" : value)
          }
        }

        IconDropdown {
          label: "Delay"
          iconText: "󰔟"
          width: toolbar.dropdownButtonWidth
          popupWidth: Style.space(100)
          value: service ? String(service.timerSeconds) : "0"
          options: [
            { value: "0", label: "None" },
            { value: "5", label: "5 sec" },
            { value: "10", label: "10 sec" }
          ]
          onChanged: function(value) { if (service) service.setTimer(value) }
        }

        GroupGap {}

        MenuButton {
          iconText: "󰆿"
          tooltipText: "Pointer: " + (service && service.includeCursor ? "On" : "Off")
          checked: service && service.includeCursor
          visible: !root.recordingMode && !root.recording
          onClicked: root.toggleBoolean("cursor")
        }

        MenuButton {
          iconText: "󰓃"
          tooltipText: "Desktop audio: " + (service && service.recordDesktopAudio ? "On" : "Off")
          checked: service && service.recordDesktopAudio
          visible: root.recordingMode || root.recording
          onClicked: root.toggleBoolean("desktopAudio")
        }

        MenuButton {
          iconText: "󰍬"
          tooltipText: "Microphone: " + (service && service.recordMicrophoneAudio ? "On" : "Off")
          checked: service && service.recordMicrophoneAudio
          visible: root.recordingMode || root.recording
          onClicked: root.toggleBoolean("microphoneAudio")
        }

        MenuButton {
          iconText: "󰄀"
          tooltipText: "Webcam: " + (service && service.recordWebcam ? "On" : "Off")
          checked: service && service.recordWebcam
          visible: root.recordingMode || root.recording
          onClicked: root.toggleBoolean("webcam")
        }

        GroupGap {}

        MenuButton {
          iconText: root.recording ? root.recordingStopIcon
            : root.recordingMode ? root.recordingPlayIcon
            : ""
          tooltipText: !root.canRunSelected ? "Select a window, screen, or region"
            : root.recording ? "Stop recording"
            : root.recordingMode ? "Record"
            : "Capture"
          cta: true
          enabled: root.canRunSelected
          opacity: enabled ? 1 : 0.45
          onClicked: root.runSelected(panel.currentScreenName)
        }
      }
    }
  }
}
