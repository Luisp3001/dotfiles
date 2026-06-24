// plugins/dock/Dock.qml — Application Dock Plugin
// macOS-style dock with cosine magnification effect and auto-hide
import QtQuick
import Quickshell
import "../../style"

Item {
    id: dock

    // ── Exposed for PanelWindow mask ─────────────────────────────────────
    property alias inputRegion: _inputRegion

    // ── State ────────────────────────────────────────────────────────────
    property bool dockShown: false
    property real globalMouseX: -1000
    property bool mouseInDock: false

    // ── Configuration ────────────────────────────────────────────────────
    readonly property int iconBaseSize: 48
    readonly property real maxScale: 1.5
    readonly property int magnifyRange: 130
    readonly property int iconSpacing: 4
    readonly property int dockPadding: 12

    // ── Hovered icon index (for tooltip + glow) ──────────────────────────
    property int hoveredIndex: {
        if (!mouseInDock) return -1
        var bestIdx = -1
        var bestScale = 1.15
        for (var i = 0; i < appsModel.count; i++) {
            var s = getIconScale(i)
            if (s > bestScale) {
                bestScale = s
                bestIdx = i
            }
        }
        return bestIdx
    }

    // ── Input region for Wayland mask ────────────────────────────────────
    // Hidden → thin strip at bottom (trigger zone)
    // Shown  → area around dock body (captures hover + clicks)
    Item {
        id: _inputRegion
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: dock.dockShown ? Math.max(dockBody.width + 80, 200) : parent.width
        height: dock.dockShown ? dock.height : 6
    }

    // ── Auto-hide timer ──────────────────────────────────────────────────
    Timer {
        id: hideTimer
        interval: 700
        onTriggered: {
            dock.dockShown = false
            dock.mouseInDock = false
            dock.globalMouseX = -1000
        }
    }

    // ── Global mouse tracking ────────────────────────────────────────────
    // Single MouseArea handles: show/hide trigger, magnification, clicks
    MouseArea {
        id: dockMouseArea
        anchors.fill: parent
        hoverEnabled: true

        onEntered: {
            dock.dockShown = true
            hideTimer.stop()
        }
        onExited: {
            dock.mouseInDock = false
            dock.globalMouseX = -1000
            hideTimer.restart()
        }
        onPositionChanged: (mouse) => {
            hideTimer.stop()
            dock.dockShown = true

            // Map mouse to dockRow coords for magnification math
            var mapped = dockMouseArea.mapToItem(dockRow, mouse.x, mouse.y)
            dock.globalMouseX = mapped.x

            // Only magnify when mouse is actually near the dock body
            var bodyMapped = dockMouseArea.mapToItem(dockBody, mouse.x, mouse.y)
            dock.mouseInDock = (bodyMapped.x >= -30 && bodyMapped.x <= dockBody.width + 30 &&
                                bodyMapped.y >= -40 && bodyMapped.y <= dockBody.height + 10)
        }
        onClicked: (mouse) => {
            if (!dock.dockShown) return
            // Hit-test each icon delegate
            for (var i = 0; i < appsModel.count; i++) {
                var item = dockRepeater.itemAt(i)
                if (!item) continue
                var mapped = dockMouseArea.mapToItem(item, mouse.x, mouse.y)
                if (mapped.x >= 0 && mapped.x <= item.width &&
                    mapped.y >= -20 && mapped.y <= item.height + 10) {
                    var app = appsModel.get(i)
                    if (app) {
                        item.bounce()
                        Quickshell.execDetached([app.command])
                    }
                    break
                }
            }
        }

        cursorShape: dock.hoveredIndex >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    // ── App model ────────────────────────────────────────────────────────
    ListModel {
        id: appsModel
        ListElement { name: "Firefox";  icon: "󰈹"; command: "firefox";  iconColor: "#ff7139" }
        ListElement { name: "Files";    icon: "󰉋"; command: "dolphin"; iconColor: "#89b4fa" }
        ListElement { name: "Terminal"; icon: "";  command: "kitty";    iconColor: "#a6e3a1" }
        ListElement { name: "Code";     icon: "󰨞"; command: "antigravity-ide";     iconColor: "#89b4fa" }
        ListElement { name: "Spotify";  icon: "󰓇"; command: "spotify";  iconColor: "#1db954" }
        ListElement { name: "Discord";  icon: "󰙯"; command: "vesktop";  iconColor: "#7289da" }
        ListElement { name: "Steam";    icon: "󰓓"; command: "steam";    iconColor: "#66c0f4" }
    }

    // ── Scale calculation (cosine-based magnification) ───────────────────
    // Uses "rest position" (uniform spacing) to avoid feedback loops.
    // The cosine curve creates a smooth, natural magnification falloff
    // identical to the classic macOS dock effect.
    function getIconScale(index) {
        if (!dock.mouseInDock) return 1.0

        // Icon center at its "rest" position (as if all icons were base size)
        var restCenter = index * (iconBaseSize + iconSpacing) + iconBaseSize / 2
        var distance = Math.abs(dock.globalMouseX - restCenter)

        if (distance >= magnifyRange) return 1.0

        // cos(0) = 1 → max scale, cos(π/2) = 0 → base scale
        return 1.0 + (maxScale - 1.0) * Math.cos((distance / magnifyRange) * (Math.PI / 2))
    }

    // ── Dock body ────────────────────────────────────────────────────────
    Rectangle {
        id: dockBody
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dock.dockShown ? 6 : -(height + 14)

        width: dockRow.width + dockPadding * 2 + 4
        height: iconBaseSize + dockPadding * 2

        color: Qt.rgba(0.06, 0.06, 0.07, 0.9)
        radius: 22
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)

        Behavior on anchors.bottomMargin {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        // Glass-effect gradient overlay
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.06) }
                GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // ── Icon Row ─────────────────────────────────────────────────────
        // Row positions icons horizontally. Each icon grows upward (bottom-anchored)
        // when magnified, creating the classic "pop up" dock effect.
        Row {
            id: dockRow
            anchors.bottom: parent.bottom
            anchors.bottomMargin: dock.dockPadding
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: dock.iconSpacing

            Repeater {
                id: dockRepeater
                model: appsModel

                delegate: Item {
                    id: iconDelegate

                    required property int index
                    required property string name
                    required property string icon
                    required property string command
                    required property string iconColor

                    // Scale from cosine magnification — recalculates on mouse move
                    property real currentScale: dock.getIconScale(index)

                    // Width varies with scale (Row spreads icons apart)
                    // Height stays fixed (icons grow upward, not downward)
                    width: dock.iconBaseSize * currentScale
                    height: dock.iconBaseSize

                    function bounce() {
                        bounceAnim.start()
                    }

                    // ── Visual icon container ────────────────────────────
                    Rectangle {
                        id: iconBg
                        width: dock.iconBaseSize * iconDelegate.currentScale * 0.85
                        height: width
                        radius: width * 0.24
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom

                        color: dock.hoveredIndex === iconDelegate.index
                            ? Qt.rgba(1, 1, 1, 0.1)
                            : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: dock.hoveredIndex === iconDelegate.index
                            ? Qt.rgba(1, 1, 1, 0.18)
                            : Qt.rgba(1, 1, 1, 0.06)

                        Behavior on color { ColorAnimation { duration: 100 } }
                        Behavior on border.color { ColorAnimation { duration: 100 } }

                        // Bounce transform (doesn't conflict with anchors)
                        transform: Translate { id: bounceTranslate; y: 0 }

                        // App icon (Nerd Font glyph)
                        Text {
                            anchors.centerIn: parent
                            text: iconDelegate.icon
                            font.family: Theme.fontMono
                            font.pixelSize: 22 * iconDelegate.currentScale
                            color: iconDelegate.iconColor
                        }

                        // Subtle colored glow when hovered
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -2
                            radius: parent.radius + 2
                            color: "transparent"
                            border.width: dock.hoveredIndex === iconDelegate.index ? 1 : 0
                            border.color: dock.hoveredIndex === iconDelegate.index
                                ? Qt.rgba(0.54, 0.7, 0.98, 0.15)
                                : "transparent"
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                    }

                    // ── Tooltip ───────────────────────────────────────────
                    Rectangle {
                        id: tooltip
                        anchors.horizontalCenter: iconBg.horizontalCenter
                        anchors.bottom: iconBg.top
                        anchors.bottomMargin: 8
                        width: tooltipText.width + 16
                        height: tooltipText.height + 8
                        radius: 8
                        color: Qt.rgba(0.08, 0.08, 0.1, 0.95)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)

                        opacity: dock.hoveredIndex === iconDelegate.index ? 1.0 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Text {
                            id: tooltipText
                            anchors.centerIn: parent
                            text: iconDelegate.name
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Theme.textPrimary
                        }
                    }

                    // ── Bounce animation (triggered on click) ────────────
                    SequentialAnimation {
                        id: bounceAnim
                        NumberAnimation {
                            target: bounceTranslate; property: "y"
                            to: -14; duration: 150
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: bounceTranslate; property: "y"
                            to: 0; duration: 350
                            easing.type: Easing.OutBounce
                        }
                    }
                }
            }
        }
    }
}
