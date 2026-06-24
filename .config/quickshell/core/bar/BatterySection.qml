// modules/bar/BatterySection.qml — Sistema: Batería + DND + Sliders
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../style"

Item {
    id: root

    property var shellRoot: null

    // ── Helpers ──────────────────────────────────────────────────────────
    function sh(cmd) { return ["bash", "-lc", cmd] }
    function det(cmd) { Quickshell.execDetached(sh(cmd)) }

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

    // ── DND Poll ────────────────────────────────────────────────────────
    property bool dnd: false
    CommandPoll {
        id: dndPoll
        running: root.visible
        interval: 4000
        command: sh("dunstctl is-paused 2>/dev/null || echo false")
        parse: function(o) { return String(o).trim() === "true" }
        onUpdated: root.dnd = value
    }
    function toggleDnd() {
        var next = !root.dnd
        root.dnd = next
        det("dunstctl set-paused " + (next ? "true" : "false"))
    }

    // ── Volume Poll ─────────────────────────────────────────────────────
    CommandPoll {
        id: volPoll
        running: root.visible
        interval: 1200
        command: sh("v=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -Po '\\d+(?=%)' | head -n1); p=$(pactl list sinks 2>/dev/null | awk \"/Name: $(pactl get-default-sink 2>/dev/null)/{f=1} f && /Active Port:/{print \\$3; exit}\"); echo \"$v|$p\"")
        parse: function(o) {
            var parts = String(o).trim().split("|")
            var n = parseInt(parts[0])
            var port = parts[1] || ""
            return { vol: isFinite(n) ? n : 0, isHeadphones: port.toLowerCase().includes("headphone") }
        }
        onUpdated: if (!volSlider.pressed) volSlider.value = value.vol
    }

    // ── Brightness Poll ─────────────────────────────────────────────────
    CommandPoll {
        id: briPoll
        running: root.visible
        interval: 1500
        command: sh("brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '% ' || true")
        parse: function(o) {
            var n = Number(String(o).trim())
            return isFinite(n) ? n : 50
        }
        onUpdated: if (!briSlider.pressed) briSlider.value = value
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
        spacing: 10

        // ── DND Toggle Row ──────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 10

            Rectangle {
                id: dndBtn
                width: parent.width
                height: 36
                radius: 12
                color: root.dnd
                    ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15)
                    : Qt.rgba(1, 1, 1, 0.06)

                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: root.dnd ? "\u{F009B}" : "\u{F009A}" // nf-md-bell_off / nf-md-bell
                        color: root.dnd ? Theme.danger : Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 15
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
        }

        // ── Separator ───────────────────────────────────────────────────
        Rectangle { width: parent.width; height: 1; color: Theme.accentDim; opacity: 0.3 }

        // ── Battery Health ───────────────────────────────────────────────
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

        // ── Separator ───────────────────────────────────────────────────
        Rectangle { width: parent.width; height: 1; color: Theme.accentDim; opacity: 0.3 }

        // ── Brightness Slider ───────────────────────────────────────────
        Row {
            width: parent.width
            height: 32
            spacing: 10

            Text {
                text: briSlider.value < 40 ? "\u{F00DF}" : (briSlider.value < 75 ? "\u{F00E0}" : "\u{F00E1}") // brightness icons
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 18
            }

            Item {
                width: parent.width - 28
                height: 32
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.06)

                    Rectangle {
                        height: parent.height
                        width: Math.max(4, parent.width * briSlider.visualPosition)
                        radius: parent.radius
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3 + briSlider.visualPosition * 0.4)
                        Behavior on width { NumberAnimation { duration: 60 } }
                    }
                }

                MouseArea {
                    id: briSliderArea
                    anchors.fill: parent
                    hoverEnabled: true

                    property bool isDragging: false

                    onPressed: (mouse) => {
                        isDragging = true
                        briSlider.value = (mouse.x / width) * 100
                    }
                    onPositionChanged: (mouse) => {
                        if (isDragging) {
                            briSlider.value = Math.max(0, Math.min(100, (mouse.x / width) * 100))
                        }
                    }
                    onReleased: {
                        isDragging = false
                        det("brightnessctl set " + Math.round(briSlider.value) + "%")
                    }
                }

                // Hidden slider for state tracking
                property alias pressed: briSlider.pressed
                Slider {
                    id: briSlider
                    visible: false
                    from: 0; to: 100
                    value: 50
                    onMoved: briDebounce.restart()
                }
                Timer {
                    id: briDebounce; interval: 70; repeat: false
                    onTriggered: det("brightnessctl set " + Math.round(briSlider.value) + "%")
                }
            }
        }

        // ── Volume Slider ───────────────────────────────────────────────
        Row {
            width: parent.width
            height: 32
            spacing: 10

            Text {
                text: {
                    if (volSlider.value === 0) return "\u{F0581}" // mute
                    if (volPoll.value && volPoll.value.isHeadphones) return "\u{F025F}" // headphones
                    return volSlider.value > 50 ? "\u{F057E}" : "\u{F0580}" // vol high / low
                }
                color: Theme.textMuted
                font.family: Theme.fontMono
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 18
            }

            Item {
                width: parent.width - 28
                height: 32
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.06)

                    Rectangle {
                        height: parent.height
                        width: Math.max(4, parent.width * volSlider.visualPosition)
                        radius: parent.radius
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3 + volSlider.visualPosition * 0.4)
                        Behavior on width { NumberAnimation { duration: 60 } }
                    }
                }

                MouseArea {
                    id: volSliderArea
                    anchors.fill: parent
                    hoverEnabled: true

                    property bool isDragging: false

                    onPressed: (mouse) => {
                        isDragging = true
                        volSlider.value = (mouse.x / width) * 100
                    }
                    onPositionChanged: (mouse) => {
                        if (isDragging) {
                            volSlider.value = Math.max(0, Math.min(100, (mouse.x / width) * 100))
                        }
                    }
                    onReleased: {
                        isDragging = false
                        det("pactl set-sink-volume @DEFAULT_SINK@ " + Math.round(volSlider.value) + "%")
                    }
                }

                property alias pressed: volSlider.pressed
                Slider {
                    id: volSlider
                    visible: false
                    from: 0; to: 100
                    value: 0
                    onMoved: volDebounce.restart()
                }
                Timer {
                    id: volDebounce; interval: 70; repeat: false
                    onTriggered: det("pactl set-sink-volume @DEFAULT_SINK@ " + Math.round(volSlider.value) + "%")
                }
            }
        }
    } // Column
    } // Flickable
}
