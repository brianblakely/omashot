pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  required property var service

  function screenNumber(screen, name, fallback) {
    var value = screen && screen[name] !== undefined ? Number(screen[name]) : Number(fallback)
    return isFinite(value) ? value : Number(fallback || 0)
  }

  function targetRectForScreen(screen) {
    if (!service || !screen) return { x: 0, y: 0, width: 0, height: 0 }
    if (service.recordingTargetScreenName !== ""
        && String(screen.name || "") !== service.recordingTargetScreenName)
      return { x: 0, y: 0, width: 0, height: 0 }

    var screenX = screenNumber(screen, "virtualX", 0)
    var screenY = screenNumber(screen, "virtualY", 0)
    var screenW = screenNumber(screen, "width", 0)
    var screenH = screenNumber(screen, "height", 0)
    var left = Math.max(service.recordingTargetX, screenX)
    var top = Math.max(service.recordingTargetY, screenY)
    var right = Math.min(service.recordingTargetX + service.recordingTargetW, screenX + screenW)
    var bottom = Math.min(service.recordingTargetY + service.recordingTargetH, screenY + screenH)

    return {
      x: left - screenX,
      y: top - screenY,
      width: Math.max(0, right - left),
      height: Math.max(0, bottom - top)
    }
  }

  function targetOverlapsScreen(screen) {
    var rect = targetRectForScreen(screen)
    return rect.width > 0 && rect.height > 0
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel

      required property var modelData

      screen: modelData
      visible: service && service.keystrokeOverlayVisible && root.targetOverlapsScreen(modelData)
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "b-omashot-keystrokes"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      readonly property var targetRect: root.targetRectForScreen(modelData)

      Rectangle {
        id: keystrokeCard

        readonly property real horizontalPadding: Style.space(14)
        readonly property real verticalPadding: Style.space(8)
        readonly property real edgeInset: panel.targetRect.width > 80 ? 40 : 0
        readonly property real availableWidth: Math.max(1, panel.targetRect.width - edgeInset * 2)

        function trimToAvailableWidth() {
          if (!service || !visible) return
          if (service.trimKeystrokes(keyRow.implicitWidth + horizontalPadding * 2, availableWidth))
            Qt.callLater(function() { keystrokeCard.trimToAvailableWidth() })
        }

        visible: service && service.keystrokeEntries.length > 0
        x: panel.targetRect.x + edgeInset
        y: Math.max(panel.targetRect.y,
          panel.targetRect.y + panel.targetRect.height - 40 - height)
        width: Math.min(availableWidth, keyRow.implicitWidth + horizontalPadding * 2)
        height: Math.min(panel.targetRect.height,
          keyRow.implicitHeight + verticalPadding * 2)
        radius: Style.cornerRadius
        color: Color.foreground
        clip: true

        onAvailableWidthChanged: Qt.callLater(function() { keystrokeCard.trimToAvailableWidth() })

        Connections {
          target: service
          function onKeystrokeEntriesChanged() {
            Qt.callLater(keystrokeCard.trimToAvailableWidth)
          }
        }

        RowLayout {
          id: keyRow

          anchors.left: parent.left
          anchors.leftMargin: keystrokeCard.horizontalPadding
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          Repeater {
            model: service ? service.keystrokeEntries : []

            RowLayout {
              id: keystrokeEntry

              required property var modelData

              Layout.alignment: Qt.AlignVCenter
              spacing: 0

              Repeater {
                model: keystrokeEntry.modelData.parts !== undefined
                    && keystrokeEntry.modelData.parts !== null
                  ? keystrokeEntry.modelData.parts
                  : [{ text: String(keystrokeEntry.modelData.text || ""), fontFamily: "" }]

                Text {
                  id: keystrokePart

                  required property var modelData
                  readonly property string requestedFontFamily: String(modelData.fontFamily || "")

                  Layout.alignment: Qt.AlignVCenter
                  text: String(modelData.text || "")
                  color: Color.background
                  font.family: requestedFontFamily !== ""
                    ? requestedFontFamily : Style.font.menuFamily
                  font.pixelSize: Style.font.body * 3
                  font.weight: requestedFontFamily !== "" ? Font.Normal : Font.DemiBold
                  renderType: requestedFontFamily !== "" ? Text.NativeRendering : Text.QtRendering
                }
              }

              Text {
                Layout.alignment: Qt.AlignVCenter
                visible: Number(keystrokeEntry.modelData.count) > 1
                text: " ×" + Number(keystrokeEntry.modelData.count)
                color: Color.background
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body * 3
                font.weight: Font.DemiBold
              }
            }
          }
        }
      }
    }
  }
}
