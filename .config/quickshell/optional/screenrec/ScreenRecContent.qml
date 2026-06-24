import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: screenRecContent
    property var rootWidget
    property var pluginWidget

    property real preferredHeight: rootWidget.screenRecState === "idle" ? 230 : 260

    // Removed background click to close as it's now a widget

    // Format time helper
    function formatTime(sec) {
        var s = Math.floor(sec % 60);
        var m = Math.floor(sec / 60);
        return (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s);
    }

    // ── Mode Selector (idle state) ─────────────────────────────────────────
    Item {
        id: selectorView
        anchors.fill: parent
        visible: opacity > 0
        opacity: rootWidget.screenRecState === "idle" ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // Icon
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰑋"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: 32
                color: rootWidget.walColors ? rootWidget.walColors.special.foreground : "#cdd6f4"
                opacity: 0.85
            }

            // Title + subtitle
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 3

                Text {
                    text: "SCREEN RECORDER"
                    Layout.alignment: Qt.AlignHCenter
                    font.family: "JetBrains Mono"
                    font.pixelSize: 11
                    font.letterSpacing: 3
                    font.weight: Font.Bold
                    color: rootWidget.walColors ? rootWidget.walColors.special.foreground : "#cdd6f4"
                }

                Text {
                    text: "Choose a recording mode"
                    Layout.alignment: Qt.AlignHCenter
                    font.family: "JetBrains Mono"
                    font.pixelSize: 10
                    color: rootWidget.walColors ? rootWidget.walColors.special.foreground : "#cdd6f4"
                    opacity: 0.45
                }
            }

            Item { Layout.fillHeight: true }

            // Mode buttons row
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                // ── Full Screen button ──────────────────────────────────
                Rectangle {
                    id: fullscreenBtn
                    width: 134
                    height: 52
                    radius: 14
                    color: fullscreenMa.containsMouse
                        ? Qt.rgba(1, 1, 1, 0.13)
                        : Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: fullscreenMa.containsMouse
                        ? Qt.rgba(1, 1, 1, 0.28)
                        : Qt.rgba(1, 1, 1, 0.09)

                    Behavior on color      { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    scale: fullscreenMa.pressed ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "󰍹"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: 20
                            color: rootWidget.walColors
                                ? rootWidget.walColors.special.foreground : "#cdd6f4"
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Full Screen"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 10
                            color: rootWidget.walColors
                                ? rootWidget.walColors.special.foreground : "#cdd6f4"
                        }
                    }

                    MouseArea {
                        id: fullscreenMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            console.log("[screenrec] fullscreen clicked, rootWidget=", rootWidget, "pluginWidget=", pluginWidget);
                            if (rootWidget) {
                                var args = [];
                                if (pluginWidget) {
                                    if (pluginWidget.recordAudio) {
                                        args.push("--audio");
                                        var dev = (pluginWidget.audioDevice || "").trim();
                                        if (dev && dev !== "default") {
                                            args.push("--audio-device", dev);
                                        }
                                    }
                                    var res = (pluginWidget.encodeResolution || "").trim();
                                    if (res && res !== "default") {
                                        args.push("--encode-resolution", res);
                                    }
                                    var fps = (pluginWidget.fps || "").trim();
                                    if (fps) {
                                        args.push("--max-fps", fps);
                                    }
                                }
                                console.log("[screenrec] calling screenRecStartFullscreen with args:", JSON.stringify(args));
                                rootWidget.screenRecStartFullscreen(args);
                            } else {
                                console.log("[screenrec] rootWidget is null/undefined — cannot start recording!");
                            }
                        }
                    }
                }

                // ── Region button ───────────────────────────────────────
                Rectangle {
                    id: regionBtn
                    width: 134
                    height: 52
                    radius: 14
                    color: regionMa.containsMouse
                        ? Qt.rgba(0.54, 0.84, 0.67, 0.13)
                        : Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: regionMa.containsMouse
                        ? Qt.rgba(0.54, 0.84, 0.67, 0.45)
                        : Qt.rgba(1, 1, 1, 0.09)

                    Behavior on color      { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    scale: regionMa.pressed ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "󰆟"
                            font.family: "Iosevka Nerd Font"
                            font.pixelSize: 20
                            color: regionMa.containsMouse ? "#a6e3a1"
                                : (rootWidget.walColors
                                    ? rootWidget.walColors.special.foreground : "#cdd6f4")
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Region"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 10
                            color: regionMa.containsMouse ? "#a6e3a1"
                                : (rootWidget.walColors
                                    ? rootWidget.walColors.special.foreground : "#cdd6f4")
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: regionMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (rootWidget) {
                                var args = [];
                                if (pluginWidget) {
                                    if (pluginWidget.recordAudio) {
                                        args.push("--audio");
                                        var dev = (pluginWidget.audioDevice || "").trim();
                                        if (dev && dev !== "default") {
                                            args.push("--audio-device", dev);
                                        }
                                    }
                                    var res = (pluginWidget.encodeResolution || "").trim();
                                    if (res && res !== "default") {
                                        args.push("--encode-resolution", res);
                                    }
                                    var fps = (pluginWidget.fps || "").trim();
                                    if (fps) {
                                        args.push("--max-fps", fps);
                                    }
                                }
                                rootWidget.screenRecStartRegion(args);
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 4 } // bottom padding
        }
    }

    // ── Recording Controls (recording / paused state) ──────────────────────
    Item {
        id: controlsView
        anchors.fill: parent
        visible: opacity > 0
        opacity: rootWidget.screenRecState !== "idle" ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 15

            // Animated Icon
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 60
                Layout.preferredHeight: 60

                Rectangle {
                    anchors.centerIn: parent
                    width: 50
                    height: 50
                    radius: 25
                    color: "transparent"
                    border.width: 2
                    border.color: rootWidget.screenRecState === "paused" ? Qt.rgba(0.95, 0.65, 0.15, 0.3) : Qt.rgba(0.94, 0.22, 0.22, 0.3)

                    SequentialAnimation on scale {
                        running: rootWidget.screenRecState === "recording"
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.4; duration: 1000; easing.type: Easing.OutQuad }
                        NumberAnimation { from: 1.4; to: 1.0; duration: 1000; easing.type: Easing.InQuad }
                    }
                    SequentialAnimation on opacity {
                        running: rootWidget.screenRecState === "recording"
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 0.0; duration: 1000; easing.type: Easing.OutQuad }
                        NumberAnimation { from: 0.0; to: 0.8; duration: 1000; easing.type: Easing.InQuad }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    radius: 17
                    color: rootWidget.screenRecState === "paused" ? Qt.rgba(0.95, 0.65, 0.15, 0.2) : Qt.rgba(0.94, 0.22, 0.22, 0.2)

                    SequentialAnimation on scale {
                        running: rootWidget.screenRecState === "recording"
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.2; duration: 1000; easing.type: Easing.OutQuad }
                        NumberAnimation { from: 1.2; to: 1.0; duration: 1000; easing.type: Easing.InQuad }
                    }
                }

                Rectangle {
                    id: coreDot
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    radius: 9
                    color: rootWidget.screenRecState === "paused" ? Qt.rgba(0.95, 0.65, 0.15, 1) : "#f03838"
                }
            }

            // Labels
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2

                Text {
                    text: rootWidget.screenRecState === "paused" ? "PAUSED" : "RECORDING"
                    color: rootWidget.screenRecState === "paused" ? Qt.rgba(0.95, 0.65, 0.15, 1) : "#f03838"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                    font.letterSpacing: 4
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: formatTime(rootWidget.screenRecElapsed)
                    color: rootWidget.walColors ? rootWidget.walColors.special.foreground : "#ffffff"
                    font.family: "JetBrains Mono"
                    font.pixelSize: 42
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true } // Spacer

            // Buttons
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 15

                Rectangle {
                    width: 140
                    height: 40
                    radius: 20
                    color: pauseMa.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.1)

                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: rootWidget.screenRecState === "paused" ? "" : ""
                            color: rootWidget.walColors ? rootWidget.walColors.special.foreground : "#ffffff"
                            font.pixelSize: 14
                        }
                        Text {
                            text: rootWidget.screenRecState === "paused" ? "Resume" : "Pause"
                            color: rootWidget.walColors ? rootWidget.walColors.special.foreground : "#ffffff"
                            font.family: "JetBrains Mono"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                    }

                    MouseArea {
                        id: pauseMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (rootWidget.screenRecState === "recording")
                                rootWidget.screenRecRunCtl("pause");
                            else if (rootWidget.screenRecState === "paused")
                                rootWidget.screenRecRunCtl("resume");
                        }
                    }
                }

                Rectangle {
                    width: 140
                    height: 40
                    radius: 20
                    color: stopMa.containsMouse ? Qt.rgba(0.94, 0.22, 0.22, 0.15) : Qt.rgba(1, 1, 1, 0.05)
                    border.width: 1
                    border.color: stopMa.containsMouse ? Qt.rgba(0.94, 0.22, 0.22, 0.5) : Qt.rgba(1, 1, 1, 0.1)

                    Behavior on color      { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: ""
                            color: stopMa.containsMouse ? "#f03838" : (rootWidget.walColors ? rootWidget.walColors.special.foreground : "#ffffff")
                            font.pixelSize: 14
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            text: "Stop"
                            color: stopMa.containsMouse ? "#f03838" : (rootWidget.walColors ? rootWidget.walColors.special.foreground : "#ffffff")
                            font.family: "JetBrains Mono"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: stopMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            rootWidget.screenRecRunCtl("stop");
                            if (rootWidget.notifOpen) rootWidget.notifOpen = false;
                        }
                    }
                }
            }
        }
    }
}
