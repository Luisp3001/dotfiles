// modules/bar/NotificationCenter.qml — Centro de notificaciones con secciones
// Panel expandido con: header (perfil + reloj), tabs superiores (widgets),
// botones de sección (Notif, WiFi, BT, Power), y contenido dinámico
import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../style"
import "../notifications"

Item {
    id: root

    property var shellRoot: null

    // ── Estado de la sección activa (dentro del tab 0) ──────────────────
    property int currentSection: 0 // 0 = Notificaciones, 1 = WiFi, 2 = Bluetooth, 3 = Power

    // ── DND State ───────────────────────────────────────────────────────
    // Lee y escribe directamente en el NotificationHandler de Quickshell
    property bool dnd: shellRoot && shellRoot.notifHandler ? shellRoot.notifHandler.dndEnabled : false
    function toggleDnd() {
        if (shellRoot && shellRoot.notifHandler) {
            shellRoot.notifHandler.dndEnabled = !shellRoot.notifHandler.dndEnabled
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // ══════════════════════════════════════════════════════════════════════
        // ── Área de contenido ───────────────────────────────────────────────
        // ══════════════════════════════════════════════════════════════════════
        Item {
            id: contentArea
            width: parent.width
            height: parent.height

            // ── Widget 0: Panel principal (Perfil + Secciones) ──────────
            Item {
                id: notifContent
                anchors.fill: parent
                opacity: root.currentSection === 4 ? 0.0 : 1.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                Column {
                    id: mainColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    // ── Header: Perfil + Reloj ──────────────────────────
                    Item {
                        id: profileRow
                        width: parent.width
                        height: 44

                        // Avatar (izquierda)
                        Rectangle {
                            id: avatarRing
                            width: 44; height: 44; radius: 22
                            color: "transparent"
                            border.color: Theme.accent; border.width: 2
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                id: avatarClip
                                anchors.fill: parent; anchors.margins: 3
                                radius: width / 2; clip: true; color: "#1c1c1c"

                                ClippingRectangle{
                                    width: 38
                                    height: 38
                                    radius: width / 2; clip: true
                                    Image {
                                        id: avatarImage
                                        anchors.fill: parent
                                        source: "file:///home/luisp/.face.icon"
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true; antialiasing: true
                                    }
                                }    
                            }
                        }

                        // Info del usuario (junto al avatar)
                        Column {
                            anchors.left: avatarRing.right
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3

                            Text {
                                text: "luisp"
                                color: Theme.textPrimary
                                font.family: Theme.fontSans; font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            Text {
                                text: "Arch Linux"
                                color: Theme.textMuted
                                font.family: Theme.fontSans; font.pixelSize: Theme.fontSizeXs
                            }
                        }

                        // Reloj (lado derecho)
                        Column {
                            id: clockCol
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            SystemClock {
                                id: clock
                                precision: SystemClock.Seconds
                            }

                            Text {
                                id: bigClock
                                text: Qt.formatDateTime(clock.date, "HH:mm")
                                color: Theme.textPrimary
                                font.family: Theme.fontMono; font.pixelSize: 28; font.weight: Font.Bold
                                anchors.right: parent.right
                            }

                            Text {
                                id: dateLabel
                                text: Qt.formatDateTime(clock.date, "ddd, d MMM")
                                color: Theme.accent
                                font.family: Theme.fontSans; font.pixelSize: Theme.fontSizeXs
                                font.capitalization: Font.AllUppercase
                                opacity: 0.85
                                anchors.right: parent.right
                            }
                        }
                    }

                    // ── Separador ────────────────────────────────────────
                    Rectangle { width: parent.width; height: 1; color: Theme.accentDim; opacity: 0.3 }

                    // ── Botones de Sección ───────────────────────────────
                    Row {
                        id: sectionRow
                        width: parent.width
                        spacing: 6

                        // Sección: Notificaciones
                        SectionButton {
                            width: (parent.width - 18) / 4
                            icon: "\u{F0009}" // bell
                            label: "Notif"
                            active: root.currentSection === 0
                            onClicked: root.currentSection = 0
                        }

                        // Sección: WiFi
                        SectionButton {
                            width: (parent.width - 18) / 4
                            icon: "󰤨" // wifi
                            label: "WiFi"
                            active: root.currentSection === 1
                            onClicked: root.currentSection = 1
                        }

                        // Sección: Bluetooth
                        SectionButton {
                            width: (parent.width - 18) / 4
                            icon: "󰂯" // bluetooth
                            label: "BT"
                            active: root.currentSection === 2
                            onClicked: root.currentSection = 2
                        }

                        // Sección: Power
                        SectionButton {
                            width: (parent.width - 18) / 4
                            icon: "󰐥" // power
                            label: "Power"
                            active: root.currentSection === 3
                            onClicked: root.currentSection = 3
                        }
                    }

                    // ── Separador ────────────────────────────────────────
                    Rectangle { width: parent.width; height: 1; color: Theme.accentDim; opacity: 0.3 }

                    // ── Contenido de la sección activa ───────────────────
                    Item {
                        id: sectionContent
                        width: parent.width
                        // Fill remaining vertical space
                        height: Math.max(0, parent.height - y)
                        clip: true

                        // Sección 0: Notificaciones + DND
                        Item {
                            anchors.fill: parent
                            opacity: root.currentSection === 0 ? 1.0 : 0.0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

                            // DND Toggle
                            Rectangle {
                                id: dndBtn
                                width: parent.width
                                height: 34
                                radius: 12
                                color: root.dnd
                                    ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15)
                                    : Qt.rgba(1, 1, 1, 0.06)

                                Behavior on color { ColorAnimation { duration: 150 } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Text {
                                        text: root.dnd ? "\u{F009B}" : "\u{F009A}" // bell_off / bell
                                        color: root.dnd ? Theme.danger : Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    Text {
                                        text: root.dnd ? "Do Not Disturb" : "Notifications On"
                                        color: root.dnd ? Theme.danger : Theme.textPrimary
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Font.DemiBold
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleDnd()
                                }
                            }

                            // Clear All Button Row
                            Item {
                                id: notifHeader
                                anchors.top: dndBtn.bottom
                                anchors.topMargin: 8
                                width: parent.width
                                height: 30
                                visible: notifList.count > 0
                                
                                Text {
                                    text: "Notificaciones"
                                    color: Theme.textMuted
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.DemiBold
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                
                                Rectangle {
                                    id: clearAllBtn
                                    width: 80; height: 24; radius: 12
                                    color: clearAllMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.2) : "transparent"
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Borrar todas"
                                        color: clearAllMa.containsMouse ? Theme.danger : Theme.textMuted
                                        font.family: Theme.fontSans
                                        font.pixelSize: Theme.fontSizeXs
                                    }
                                    
                                    MouseArea {
                                        id: clearAllMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.shellRoot && root.shellRoot.notifHistory) {
                                                root.shellRoot.notifHistory.clearAll();
                                            }
                                        }
                                    }
                                }
                            }

                            ListView {
                                id: notifList
                                anchors.top: notifHeader.visible ? notifHeader.bottom : dndBtn.bottom
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.topMargin: 8
                                clip: true; spacing: 6
                                model: root.shellRoot ? root.shellRoot.notifHistory.model : null

                                delegate: NotifItem {
                                    width: notifList.width
                                    nId: model.notifId; app: model.appName
                                    summary: model.summary; body: model.body
                                    image: model.image; time: model.time
                                    onClicked: { }
                                    onClosed: {
                                        if (root.shellRoot && root.shellRoot.notifHistory) {
                                            root.shellRoot.notifHistory.removeAt(index);
                                        }
                                    }
                                }

                                Item {
                                    width: parent.width; height: 20
                                    visible: notifList.count === 0
                                    anchors.centerIn: parent

                                    Row {
                                        anchors.centerIn: parent; spacing: 6
                                        Text {
                                            text: "\u{F0292}"; color: Theme.textMuted
                                            font.family: Theme.fontMono; font.pixelSize: 13
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Sin notificaciones"; color: Theme.textMuted
                                            font.family: Theme.fontSans; font.pixelSize: Theme.fontSizeSm
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }

                        // Sección 1: WiFi
                        Item {
                            anchors.fill: parent
                            opacity: root.currentSection === 1 ? 1.0 : 0.0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

                            WifiSection {
                                anchors.fill: parent
                                shellRoot: root.shellRoot
                            }
                        }

                        // Sección 2: Bluetooth
                        Item {
                            anchors.fill: parent
                            opacity: root.currentSection === 2 ? 1.0 : 0.0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

                            BluetoothSection {
                                anchors.fill: parent
                                shellRoot: root.shellRoot
                            }
                        }

                        // Sección 3: Power Menu
                        Item {
                            anchors.fill: parent
                            opacity: root.currentSection === 3 ? 1.0 : 0.0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }

                            PowerSection {
                                anchors.fill: parent
                                shellRoot: root.shellRoot
                            }
                        }
                    }
                }
            }

            // ── Widget 1: Plugins ───────────────────────────────────────
            Item {
                id: pluginsContent
                anchors.fill: parent
                opacity: root.currentSection === 4 ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                PluginsWidget {
                    anchors.fill: parent
                    shellRoot: root.shellRoot
                }
            }
        }
    }


    // ── Componente: Botón de Sección ────────────────────────────────────
    component SectionButton: Rectangle {
        id: secBtn
        property string icon: ""
        property string label: ""
        property bool active: false
        signal clicked()

        height: 34
        radius: 8
        color: active
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
            : (secBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

        border.width: active ? 1 : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)

        Behavior on color { ColorAnimation { duration: 150 } }

        Column {
            anchors.centerIn: parent
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: secBtn.icon
                color: secBtn.active ? Theme.accent : Theme.textMuted
                font.family: Theme.fontMono; font.pixelSize: 13
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: secBtn.label
                color: secBtn.active ? Theme.accent : Theme.textMuted
                font.family: Theme.fontSans; font.pixelSize: 9
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        MouseArea {
            id: secBtnMouse
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: secBtn.clicked()
        }

        // Micro-animation: gentle scale on press
        scale: secBtnMouse.pressed ? 0.95 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
}
