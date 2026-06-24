import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.DBusMenu
import "../style"

DropdownWindow {
  id: menu

  implicitWidth: 220
  implicitHeight: menuColumn.implicitHeight + 20

  // Menu model from QsMenuOpener.children
  required property var model
  signal itemTriggered()

  ColumnLayout {
    id: menuColumn
    spacing: 4
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      margins: 10
    }

    Repeater {
      model: menu.model

      Rectangle {
        id: menuItemRect
        required property QsMenuEntry modelData

        Layout.fillWidth: true
        implicitHeight: modelData.isSeparator ? 1 : 32
        radius: 8
        color: {
          if (modelData.isSeparator) return "transparent";
          if (itemMouse.containsMouse) {
            return menu.walColors
              ? Qt.rgba(
                  menu.walColors.colors.color4.r,
                  menu.walColors.colors.color4.g,
                  menu.walColors.colors.color4.b,
                  0.18)
              : Qt.rgba(0.537, 0.706, 0.980, 0.18); // Theme.accent aproximado con alpha
          }
          return "transparent";
        }

        Behavior on color {
          ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        // Separator line
        Rectangle {
          visible: modelData.isSeparator
          anchors.centerIn: parent
          width: parent.width - 16
          height: 1
          color: menu.walColors
            ? Qt.rgba(
                menu.walColors.colors.color7.r,
                menu.walColors.colors.color7.g,
                menu.walColors.colors.color7.b,
                0.15)
            : Theme.accentDim
        }

        // Menu item text
        Text {
          visible: !modelData.isSeparator
          anchors {
            left: parent.left
            leftMargin: 10
            verticalCenter: parent.verticalCenter
          }
          text: modelData.text ?? ""
          color: {
            if (modelData.enabled === false) {
              return menu.walColors
                ? Qt.rgba(
                    menu.walColors.special.foreground.r,
                    menu.walColors.special.foreground.g,
                    menu.walColors.special.foreground.b,
                    1)
                : Theme.textMuted;
            }
            return menu.walColors
              ? menu.walColors.special.foreground
              : Theme.textPrimary;
          }
          font.pixelSize: 13
        }

        MouseArea {
          id: itemMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: !modelData.isSeparator && modelData.enabled !== false
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

          onClicked: {
            modelData.triggered();
            menu.itemTriggered();
          }
        }
      }
    }
  }
}