// components/WorkspaceIndicator.qml — Indicador de workspaces de Hyprland
import QtQuick
import QtQuick.Controls
import Quickshell.Hyprland
import "../../style"

Item {
    id: root

    implicitWidth: row.implicitWidth + Theme.pillPadding * 2
    implicitHeight: row.implicitHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing - 2

        Repeater {
            model: Hyprland.workspaces

            delegate: Item {
                id: wsDot
                required property var modelData

                // Propiedades del delegate — NO de modelData
                readonly property bool isActive: modelData.id === Hyprland.focusedWorkspace?.id
                readonly property bool isUrgent: modelData.urgent

                width: isActive ? 20 : 8
                height: 8
                anchors.verticalCenter: parent.verticalCenter

                // Animación suave al cambiar de workspace
                Behavior on width {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                Rectangle {
                    id: dotRect
                    anchors.fill: parent
                    radius: height / 2
                    // Usamos las propiedades del delegate (isActive), no de modelData
                    color:   wsDot.isActive ? Theme.accent : (wsDot.isUrgent ? Theme.danger : Theme.accentDim)
                    opacity: (wsDot.isActive || wsDot.isUrgent) ? 1.0 : 0.5

                    SequentialAnimation {
                        id: pulseAnim
                        running: wsDot.isUrgent && !wsDot.isActive
                        loops: Animation.Infinite
                        NumberAnimation { target: dotRect; property: "opacity"; from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: dotRect; property: "opacity"; from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    Behavior on opacity {
                        enabled: !pulseAnim.running
                        NumberAnimation { duration: 150 }
                    }
                }

                // MouseArea + ToolTip (requiere QtQuick.Controls para attached props)
                MouseArea {
                    id: wsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + wsDot.modelData.id)
                }

                ToolTip {
                    visible: wsArea.containsMouse
                    text: wsDot.modelData.name !== "" ? wsDot.modelData.name : String(wsDot.modelData.id)
                    delay: 500
                }
            }
        }
    }
}
