// modules/bar/PowerSection.qml — Sección de Power Menu
import QtQuick
import Quickshell
import "../../style"

Item {
    id: root

    property var shellRoot: null

    Column {
        anchors.fill: parent
        spacing: 16

        // ── Title ───────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 2

            Text {
                text: "Power"
                color: Theme.textPrimary
                font.family: Theme.fontSans
                font.pixelSize: 14
                font.weight: Font.Bold
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "Manage your session"
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontSizeXs
                opacity: 0.7
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        // ── Separator ───────────────────────────────────────────────
        Rectangle { width: parent.width; height: 1; color: Theme.accentDim; opacity: 0.2 }

        // ── Top Row: Lock + Logout + Suspend ────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            PowerCard {
                icon: "󰌾"
                label: "Lock"
                sublabel: "hyprlock"
                cardColor: Theme.accent
                onClicked: Quickshell.execDetached(["hyprlock"])
            }

            PowerCard {
                icon: "󰍃"
                label: "Logout"
                sublabel: "hyprland"
                cardColor: Theme.warning
                onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "exit"])
            }

            PowerCard {
                icon: "󰤄"
                label: "Suspend"
                sublabel: "sleep"
                cardColor: Theme.accent
                onClicked: Quickshell.execDetached(["systemctl", "suspend"])
            }
        }

        // ── Bottom Row: Reboot + Shutdown ───────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            PowerCard {
                icon: "󰜉"
                label: "Reboot"
                sublabel: "systemctl"
                cardColor: Theme.warning
                onClicked: Quickshell.execDetached(["systemctl", "reboot"])
            }

            PowerCard {
                icon: "󰐥"
                label: "Shutdown"
                sublabel: "poweroff"
                cardColor: Theme.danger
                onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
            }
        }
    }

    // ── Componente: PowerCard ────────────────────────────────────────
    component PowerCard: Rectangle {
        id: card
        property string icon: ""
        property string label: ""
        property string sublabel: ""
        property color cardColor: Theme.accent
        signal clicked()

        width: 80; height: 80; radius: 16
        color: cardMouse.containsMouse
            ? Qt.rgba(card.cardColor.r, card.cardColor.g, card.cardColor.b, 0.15)
            : Qt.rgba(1, 1, 1, 0.04)
        border.width: cardMouse.containsMouse ? 1 : 1
        border.color: cardMouse.containsMouse
            ? Qt.rgba(card.cardColor.r, card.cardColor.g, card.cardColor.b, 0.35)
            : Qt.rgba(1, 1, 1, 0.06)

        Behavior on color { ColorAnimation { duration: 180 } }
        Behavior on border.color { ColorAnimation { duration: 180 } }

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: card.icon
                color: cardMouse.containsMouse ? card.cardColor : Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 22
                anchors.horizontalCenter: parent.horizontalCenter
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Text {
                text: card.label
                color: cardMouse.containsMouse ? card.cardColor : Theme.textPrimary
                font.family: Theme.fontSans
                font.pixelSize: 11
                font.weight: Font.DemiBold
                anchors.horizontalCenter: parent.horizontalCenter
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            Text {
                text: card.sublabel
                color: Theme.textMuted
                font.family: Theme.fontSans
                font.pixelSize: 8
                opacity: 0.6
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
        }

        scale: cardMouse.pressed ? 0.92 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
}
