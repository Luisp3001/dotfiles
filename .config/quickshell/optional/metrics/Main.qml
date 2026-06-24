// optional/metrics/Main.qml — System Metrics Plugin
// Type: widget — expone barIcon + expandedPanel
import QtQuick
import Quickshell
import Caelestia.Services
import "../../style"

Item {
    id: widget

    // Inyectado por PluginManager
    property string pluginId: ""

    // Inyectados por Bar.qml
    property var shellRoot: null
    property var rootWidget: null

    // Indica si la pestaña de este plugin está activa en el CenterSection
    property bool isCenterTabActive: false

    // Icono personalizado para la pestaña global
    property string tabIcon: "󰍹"

    readonly property int expandedWidth: 500
    readonly property int expandedHeight: 260

    // Service references to ensure background data is fetched
    Loader {
        active: widget.isCenterTabActive || (widget.rootWidget && widget.rootWidget.activeDynamicWidget === widget)
        sourceComponent: Component {
            Item {
                ServiceRef { service: Cpu }
                ServiceRef { service: Memory }
            }
        }
    }

    readonly property int cpuPercent: Math.round(Cpu.percentage * 100)
    readonly property int ramPercent: Math.round(Memory.percentage * 100)
    readonly property int tempC: Math.round(Cpu.temperature)

    // ── barIcon ───────────────────────────────────────────────────────────
    property Component barIcon: Component {
        Item {
            implicitWidth: 24
            implicitHeight: 24

            width: widget.isCenterTabActive ? 0 : implicitWidth
            opacity: widget.isCenterTabActive ? 0.0 : 1.0
            visible: opacity > 0
            clip: true

            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

            Component.onCompleted: {
                if (shellRoot && widget.shellRoot !== shellRoot) widget.shellRoot = shellRoot
                if (rootWidget && widget.rootWidget !== rootWidget) widget.rootWidget = rootWidget
            }

            Text {
                id: iconText
                anchors.centerIn: parent
                text: "󰍹"
                font.family: Theme.fontMono
                font.pixelSize: 16
                color: Theme.textMuted
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (widget.rootWidget) widget.rootWidget.toggleDynamicWidget(widget)
                }
                onEntered: iconText.color = Theme.accent
                onExited: iconText.color = Theme.textMuted
            }
        }
    }

    // ── centerWidget ──────────────────────────────────────────────────────
    // Componente que se muestra como pestaña en el CenterSection de la isla
    property Component centerWidget: Component {
        Item {
            implicitWidth: centerRow.implicitWidth
            implicitHeight: 24

            Row {
                id: centerRow
                anchors.centerIn: parent
                spacing: 10

                // CPU
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "󰻠"
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                        color: Theme.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: widget.cpuPercent + "%"
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // RAM
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "󰘚"
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                        color: Theme.success
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: widget.ramPercent + "%"
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Temp
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "󰔏"
                        font.family: Theme.fontMono
                        font.pixelSize: 13
                        color: widget.tempC > 70 ? Theme.danger : (widget.tempC > 50 ? Theme.warning : Theme.accent)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: widget.tempC + "°C"
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // ── expandedPanel ─────────────────────────────────────────────────────
    property Component expandedPanel: Component {
        Item {
            Component.onCompleted: {
                if (shellRoot && widget.shellRoot !== shellRoot) widget.shellRoot = shellRoot
                if (rootWidget && widget.rootWidget !== rootWidget) widget.rootWidget = rootWidget
            }

            SystemWidget {
                anchors.fill: parent
                shellRoot: widget.shellRoot
            }
        }
    }
}
