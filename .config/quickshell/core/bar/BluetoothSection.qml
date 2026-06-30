// modules/bar/BluetoothSection.qml — Bluetooth menu embebido para el centro de notificaciones
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../style"

Item {
    id: root

    property var shellRoot: null

    // ── Colors ──────────────────────────────────────────────────────────
    readonly property color cFg:     Theme.textPrimary
    readonly property color cMuted:  Theme.textMuted
    readonly property color cBlue:   Theme.accent
    readonly property color cRed:    Theme.danger
    readonly property color cBorder: Theme.accentDim
    readonly property color cBgAlt:  Qt.rgba(1, 1, 1, 0.06)
    readonly property color cCard:   Theme.bgPill

    readonly property string fontText: Theme.fontSans
    readonly property string fontIcon: Theme.fontMono

    // ── State ───────────────────────────────────────────────────────────
    property bool isBusy: false
    property bool btEnabled: false
    property bool scanRunning: false
    property string statusLine: ""
    property color statusColor: cMuted

    ListModel { id: deviceModel }

    onVisibleChanged: {
        if (visible) { refreshStatus() }
        else { scanRunning = false }
    }

    Timer { id: statusTimer; interval: 3000; repeat: false; onTriggered: statusLine = "" }

    function setStatus(msg, isError) {
        statusLine = msg; statusColor = isError ? cRed : cMuted; statusTimer.restart()
    }

    // ── Status Process ──────────────────────────────────────────────────
    Process {
        id: procStatus
        command: ["bash", "-c", `
            if ! command -v bluetoothctl >/dev/null 2>&1; then echo "ERROR:bluez-utils-missing"; exit 0; fi
            if ! pidof bluetoothd >/dev/null 2>&1; then echo "ERROR:bluetoothd-missing"; exit 0; fi
            if bluetoothctl show | grep -q "Powered: yes"; then echo "POWER:on"; else echo "POWER:off"; exit 0; fi
            bluetoothctl devices | while read -r _ mac name; do
                if [ -z "$mac" ]; then continue; fi
                info=$(bluetoothctl info "$mac" 2>/dev/null)
                conn=$(echo "$info" | grep -q "Connected: yes" && echo "true" || echo "false")
                paired=$(echo "$info" | grep -q "Paired: yes" && echo "true" || echo "false")
                trusted=$(echo "$info" | grep -q "Trusted: yes" && echo "true" || echo "false")
                echo "DEV|$mac|$name|$conn|$paired|$trusted"
            done
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                isBusy = false; deviceModel.clear()
                const lines = String(text || "").split(/\r?\n/)
                for (let line of lines) {
                    if (!line) continue
                    if (line.startsWith("ERROR:bluez-utils-missing")) { setStatus("bluez-utils missing", true); btEnabled = false; return }
                    if (line.startsWith("ERROR:bluetoothd-missing")) { setStatus("Bluetooth service not running", true); btEnabled = false; return }
                    if (line.startsWith("POWER:on")) btEnabled = true
                    else if (line.startsWith("POWER:off")) btEnabled = false
                    else if (line.startsWith("DEV|")) {
                        const parts = line.split("|")
                        if (parts.length >= 6) {
                            deviceModel.append({
                                mac: parts[1], name: parts[2] || "Unknown Device",
                                connected: parts[3] === "true", paired: parts[4] === "true", trusted: parts[5] === "true"
                            })
                        }
                    }
                }
            }
        }
        onExited: (exitCode) => { if (exitCode !== 0) { isBusy = false; setStatus("Failed to fetch status", true) } }
    }

    function refreshStatus() { if (isBusy) return; isBusy = true; procStatus.running = true }

    // ── Action Process ──────────────────────────────────────────────────
    Process {
        id: procAction
        stdout: StdioCollector { onStreamFinished: { isBusy = false; refreshStatus() } }
        onExited: (exitCode) => { if (exitCode !== 0) { isBusy = false; setStatus("Action failed", true); refreshStatus() } }
    }

    function runBtCommand(cmdStr) {
        if (isBusy) return; isBusy = true
        procAction.command = ["bash", "-c", cmdStr]; procAction.running = true
    }

    function togglePower() { runBtCommand("bluetoothctl power " + (btEnabled ? "off" : "on")) }

    function toggleConnection(mac, isConnected, isPaired) {
        if (!isPaired) {
            setStatus("Opening pairing manager...", false)
            Quickshell.execDetached(["blueman-manager"])
            return
        }
        if (isConnected) { setStatus("Disconnecting...", false); runBtCommand("bluetoothctl disconnect " + mac) }
        else { setStatus("Connecting...", false); runBtCommand("bluetoothctl connect " + mac) }
    }

    function toggleScan() {
        scanRunning = !scanRunning
        if (scanRunning) {
            setStatus("Scanning...", false)
            Quickshell.execDetached(["bash", "-c", "bluetoothctl --timeout 10 scan on"])
            scanTimer.restart()
        } else {
            Quickshell.execDetached(["bash", "-c", "bluetoothctl scan off"])
            setStatus("Scan stopped", false); refreshStatus()
        }
    }

    Timer { id: scanTimer; interval: 10500; repeat: false; onTriggered: { scanRunning = false; refreshStatus() } }

    // ── Periodic refresh ────────────────────────────────────────────────
    Timer {
        interval: 5000; repeat: true; running: root.visible
        onTriggered: { if (!isBusy) refreshStatus() }
    }

    Component.onCompleted: refreshStatus()

    // ── UI ──────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: " Bluetooth"
                color: cFg; font.family: fontText; font.pixelSize: 14; font.weight: Font.Bold
                Layout.fillWidth: true
            }

            Rectangle {
                width: 42; height: 22; radius: 11
                color: btEnabled ? Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.95) : cBgAlt
                border.width: 1
                border.color: btEnabled ? Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.55) : cBorder
                opacity: isBusy ? 0.6 : 1.0
                Rectangle {
                    width: 16; height: 16; radius: 8; color: cCard
                    anchors.verticalCenter: parent.verticalCenter
                    x: btEnabled ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor; enabled: !isBusy
                    onClicked: togglePower()
                }
            }
        }

        // ── Devices Header ──────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Devices"; font.family: fontText; font.pixelSize: 12; font.weight: Font.Bold
                color: cFg; Layout.fillWidth: true
            }

            Rectangle {
                width: 28; height: 28; radius: 14
                color: scanHover.containsMouse ? cBgAlt : "transparent"
                opacity: btEnabled ? 1.0 : 0.4

                Text {
                    anchors.centerIn: parent; text: "󰑐"
                    font.family: fontIcon; font.pixelSize: 14
                    color: scanRunning ? cBlue : cFg
                    RotationAnimation on rotation {
                        loops: Animation.Infinite; from: 0; to: 360; duration: 1000; running: scanRunning
                    }
                }
                MouseArea {
                    id: scanHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; enabled: btEnabled && !isBusy
                    onClicked: toggleScan()
                }
            }
        }

        // ── Device List ─────────────────────────────────────────────────
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            model: deviceModel; spacing: 3

            delegate: Rectangle {
                width: ListView.view.width; height: 42; radius: 10
                color: devMouse.containsMouse ? cBgAlt : "transparent"
                border.width: devMouse.containsMouse ? 1 : 0
                border.color: Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.25)

                RowLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 8
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: model.connected ? Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.15) : "transparent"
                        Text {
                            anchors.centerIn: parent; text: model.connected ? "󰂱" : "󰂯"
                            font.family: fontIcon; font.pixelSize: 15
                            color: model.connected ? cBlue : cMuted
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 1
                        Text {
                            text: model.name; font.family: fontText; font.pixelSize: 12
                            font.weight: model.connected ? Font.Bold : Font.Medium
                            color: model.connected ? cBlue : cFg; elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        Text {
                            text: model.connected ? "Connected" : (model.paired ? "Paired" : "Not paired")
                            font.family: fontText; font.pixelSize: 9; color: cMuted; Layout.fillWidth: true
                        }
                    }
                }
                MouseArea {
                    id: devMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor; enabled: !isBusy && btEnabled
                    onClicked: toggleConnection(model.mac, model.connected, model.paired)
                }
            }

            Text {
                visible: deviceModel.count === 0; anchors.centerIn: parent
                text: btEnabled ? "No devices found.\nClick scan to discover." : "Bluetooth is turned off"
                horizontalAlignment: Text.AlignHCenter; font.family: fontText; font.pixelSize: 12; color: cMuted
            }
        }

        // ── Status Line ─────────────────────────────────────────────────
        Text {
            text: statusLine; visible: statusLine.length > 0
            font.family: fontText; font.pixelSize: 10; color: statusColor
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
