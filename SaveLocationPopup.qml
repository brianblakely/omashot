import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

Controls.Popup {
  id: root

  property string currentPath: ""
  property string homePath: ""

  signal chosen(string path)

  function submit() {
    if (pathInput.text.charAt(0) !== "/") return
    chosen(pathInput.text)
    close()
  }

  anchors.centerIn: parent
  width: Math.min(Style.space(420), parent ? parent.width : Style.space(420))
  padding: Style.spacing.lg
  modal: true
  dim: false
  focus: true
  closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

  onAboutToShow: pathInput.text = currentPath.charAt(0) === "/" ? currentPath : homePath + "/"
  onOpened: {
    pathInput.forceActiveFocus()
    pathInput.cursorPosition = pathInput.text.length
  }

  background: Rectangle {
    color: Color.menu.background
    border.color: Color.menu.border
    border.width: Style.normalBorderWidth
    radius: Style.cornerRadius
  }

  contentItem: Column {
    spacing: Style.spacing.md

    Text {
      width: parent.width
      text: "Custom save folder"
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }

    TextField {
      id: pathInput
      width: parent.width
      placeholderText: "Absolute folder path"
      foreground: Color.menu.text
      accent: Color.menu.selectedText
      onAccepted: root.submit()
    }

    Text {
      width: parent.width
      text: "Enter a full path starting with /. Screenshots and recordings will be saved here."
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }

    Row {
      anchors.right: parent.right
      spacing: Style.spacing.sm

      Button {
        text: "Cancel"
        foreground: Color.menu.text
        accent: Color.menu.selectedText
        focusable: true
        onClicked: root.close()
      }

      Button {
        text: "Save"
        foreground: Color.menu.text
        accent: Color.menu.selectedText
        focusable: true
        bordered: true
        enabled: pathInput.text.charAt(0) === "/"
        opacity: enabled ? 1 : 0.5
        onClicked: root.submit()
      }
    }
  }
}
