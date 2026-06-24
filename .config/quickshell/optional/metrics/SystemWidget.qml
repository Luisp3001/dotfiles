// modules/bar/SystemWidget.qml — Métricas del sistema: Batería + CPU + RAM + Temp + Uptime
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Services
import "../../style"
import "../../core/bar"

Item {
    id: root

    property var shellRoot: null

    // ── Helpers ──────────────────────────────────────────────────────────
    function sh(cmd) { return ["bash", "-lc", cmd] }

    // ── Battery Poll ────────────────────────────────────────────────────
    CommandPoll {
        id: batteryPoll
        running: root.visible
        interval: 8000
        command: sh("upower -i /org/freedesktop/UPower/devices/battery_BAT0 2>/dev/null || true")
        parse: function(out) {
            var info = {
                percentage: 0, capacity: 0, cycles: 0,
                energyFull: "", energyFullDesign: "",
                timeRemaining: "", state: ""
            }
            var lines = String(out || "").split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (!line || line.indexOf(":") === -1) continue
                var parts = line.split(":")
                var key = parts.shift().trim().toLowerCase()
                var value = parts.join(":").trim()
                if (key === "percentage") info.percentage = parseFloat(value)
                else if (key === "capacity") info.capacity = parseFloat(value)
                else if (key === "charge cycles" || key === "charge-cycles") info.cycles = parseInt(value)
                else if (key === "energy-full") info.energyFull = value
                else if (key === "energy-full-design") info.energyFullDesign = value
                else if (key === "time to empty" || key === "time to full") info.timeRemaining = value
                else if (key === "state") info.state = value
            }
            return info
        }
    }

    readonly property var batteryInfo: batteryPoll.value || ({})
    readonly property real healthPercent: Math.max(0, Math.min(100, Number(batteryInfo.capacity) || 0))
    readonly property string cyclesText: isFinite(batteryInfo.cycles) && batteryInfo.cycles > 0 ? String(batteryInfo.cycles) : "—"
    readonly property string energyText: (batteryInfo.energyFull && batteryInfo.energyFullDesign)
        ? (batteryInfo.energyFull + " / " + batteryInfo.energyFullDesign) : "—"
    readonly property string timeText: batteryInfo.timeRemaining
        || (batteryInfo.state === "fully-charged" ? "Full" : "—")
    readonly property string stateText: batteryInfo.state
        ? (batteryInfo.state.charAt(0).toUpperCase() + batteryInfo.state.slice(1)) : "Unknown"

    // ── System metrics from Caelestia ───────────────────────────────────
    Loader {
        active: root.visible
        sourceComponent: Component {
            Item {
                ServiceRef { service: Cpu }
                ServiceRef { service: Memory }
            }
        }
    }

    readonly property int cpuPercent: Math.round(Cpu.percentage * 100)
    readonly property string ramUsed: (Memory.used / 1048576).toFixed(1)
    readonly property string ramTotal: (Memory.total / 1048576).toFixed(1)
    readonly property int ramPercent: Math.round(Memory.percentage * 100)
    readonly property int tempC: Math.round(Cpu.temperature)
    readonly property int uptimeSec: shellRoot ? shellRoot.sysUptime : 0

    function formatUptime(seconds) {
        var d = Math.floor(seconds / 86400);
        var h = Math.floor((seconds % 86400) / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        if (d > 0) return d + "d " + h + "h " + m + "m";
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    // ── UI ──────────────────────────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: innerCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

    Column {
        id: innerCol
        width: parent.width
        anchors.margins: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        // ── Battery Health ───────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6

            Item {
                width: parent.width
                height: 20

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        text: "Battery Health  "
                        color: Theme.textPrimary
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "󱟢"
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.stateText
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                }
            }

            // Capacity + Charge row
            Row {
                width: parent.width

                Text {
                    text: Math.round(root.healthPercent) + "% capacity"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    width: parent.width / 2
                }

                Text {
                    text: "Charge " + Math.round(Number(batteryInfo.percentage) || 0) + "%"
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    width: parent.width / 2
                    horizontalAlignment: Text.AlignRight
                }
            }

            // Health Bar
            Rectangle {
                width: parent.width
                height: 7
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.08)

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: Math.max(4, parent.width * (root.healthPercent / 100))
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                }
            }

            // Stats row: Cycles | Energy | Time
            Row {
                width: parent.width
                spacing: 8

                Column {
                    width: (parent.width - 16) / 3
                    spacing: 1
                    Text {
                        text: "Cycles"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        opacity: 0.8
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: root.cyclesText
                        color: Theme.textPrimary
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                Column {
                    width: (parent.width - 16) / 3
                    spacing: 1
                    Text {
                        text: "Energy (full/design)"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        opacity: 0.8
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: root.energyText
                        color: Theme.textPrimary
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                Column {
                    width: (parent.width - 16) / 3
                    spacing: 1
                    Text {
                        text: "Time remaining"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        opacity: 0.8
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: root.timeText
                        color: Theme.textPrimary
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }

        // ── Separator ───────────────────────────────────────────────
        Rectangle { width: parent.width; height: 1; color: Theme.accentDim; opacity: 0.3 }

        // ── System Metrics ──────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 8

            // CPU Card
            Rectangle {
                width: (parent.width - 16) / 3
                height: 70
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰻠"
                        color: Theme.accent
                        font.family: Theme.fontMono
                        font.pixelSize: 18
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: root.cpuPercent + "%"
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "CPU"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // RAM Card
            Rectangle {
                width: (parent.width - 16) / 3
                height: 70
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰘚"
                        color: Theme.success
                        font.family: Theme.fontMono
                        font.pixelSize: 18
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: root.ramUsed + "G"
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "RAM " + root.ramPercent + "%"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // Temperature Card
            Rectangle {
                width: (parent.width - 16) / 3
                height: 70
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "󰔏"
                        color: root.tempC > 70 ? Theme.danger : (root.tempC > 50 ? Theme.warning : Theme.accent)
                        font.family: Theme.fontMono
                        font.pixelSize: 18
                        anchors.horizontalCenter: parent.horizontalCenter
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }

                    Text {
                        text: root.tempC + "°C"
                        color: Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "TEMP"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 9
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }

        // ── Uptime ──────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 36
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)

            Row {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: "󰥔"
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Uptime"
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontSizeSm
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.formatUptime(root.uptimeSec)
                    color: Theme.textPrimary
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSizeSm
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    } // Column
    } // Flickable
}
