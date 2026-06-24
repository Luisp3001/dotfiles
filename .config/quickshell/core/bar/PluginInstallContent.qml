// modules/bar/PluginInstallContent.qml — Plugin install UI for the Dynamic Island
// Shows plugin info + Install/Cancel buttons when a plugin folder is dropped.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../style"

Item {
    id: installContent

    // ── Interface ────────────────────────────────────────────────────────
    property var rootWidget
    property var pluginManager: null

    // Plugin metadata (set from Bar.qml after detection)
    property string pluginId: ""
    property string pluginName: ""
    property string pluginDescription: ""
    property string pluginVersion: ""
    property string pluginAuthor: ""
    property string pluginMain: "Main.qml"
    property string pluginType: "window"
    property string sourcePath: ""

    // State: confirm | installing | installed | error
    property string installState: "confirm"
    property string errorMessage: ""

    // Height adapts to state
    property int preferredHeight: {
        if (installState === "confirm") return 200
        if (installState === "installing") return 160
        return 150 // installed / error
    }

    // ── Set plugin data from manifest ────────────────────────────────────
    function setPlugin(path, manifest) {
        sourcePath = path
        pluginId = manifest.id || ""
        pluginName = manifest.name || "Unknown Plugin"
        pluginDescription = manifest.description || ""
        pluginVersion = manifest.version || "1.0.0"
        pluginAuthor = manifest.author || ""
        pluginMain = manifest.main || "Main.qml"
        pluginType = manifest.type || "window"
        installState = "confirm"
        errorMessage = ""
    }

    // ── Reset ────────────────────────────────────────────────────────────
    function reset() {
        installState = "confirm"
        pluginId = ""
        pluginName = ""
        pluginDescription = ""
        pluginVersion = ""
        pluginAuthor = ""
        sourcePath = ""
        errorMessage = ""
        copyProc.running = false
    }

    // ── Copy process ─────────────────────────────────────────────────────
    // Copies plugin folder to ~/.config/quickshell/plugins/<folder-name>/
    Process {
        id: copyProc
        property string destPath: ""

        onExited: (code) => {
            if (code === 0) {
                // Copy success → register in PluginManager
                if (installContent.pluginManager) {
                    var relPath = "optional/" + installContent.sourcePath.split('/').pop()
                    installContent.pluginManager.installPlugin(
                        installContent.pluginId,
                        relPath,
                        installContent.pluginName,
                        installContent.pluginMain,
                        installContent.pluginType
                    )
                }
                installContent.installState = "installed"
                autoCloseTimer.start()
            } else {
                installContent.installState = "error"
                installContent.errorMessage = "Copy failed (exit code " + code + ")"
                autoCloseTimer.start()
            }
        }
    }

    // ── Auto-close timer ─────────────────────────────────────────────────
    Timer {
        id: autoCloseTimer
        interval: 2500
        onTriggered: {
            if (rootWidget) {
                rootWidget.pluginDropMode = false
                rootWidget.togglePluginInstall()
            }
            installContent.reset()
        }
    }

    // ── Install action ───────────────────────────────────────────────────
    function startInstall() {
        if (sourcePath === "" || pluginId === "") return

        installState = "installing"

        var folderName = sourcePath.split('/').pop()
        var configDir = Quickshell.env("HOME") + "/.config/quickshell/optional/" + folderName
        copyProc.destPath = configDir
        copyProc.command = ["bash", "-c", "mkdir -p '" + configDir + "' && cp -r '" + sourcePath + "/'* '" + configDir + "/'"]
        copyProc.running = true
    }

    // ── Cancel action ────────────────────────────────────────────────────
    function cancel() {
        copyProc.running = false
        if (rootWidget) {
            rootWidget.pluginDropMode = false
            rootWidget.togglePluginInstall()
        }
        reset()
    }

    // ══════════════════════════════════════════════════════════════════════
    // ── Visual UI ────────────────────────────────────────────────────────
    // ══════════════════════════════════════════════════════════════════════

    // ── Confirm State ────────────────────────────────────────────────────
    Column {
        id: confirmView
        anchors.fill: parent
        anchors.margins: 4
        spacing: 10
        visible: installContent.installState === "confirm"
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Header
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Text {
                text: "󰏗"
                font.family: Theme.fontMono
                font.pixelSize: 20
                color: "#89b4fa"
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Plugin detected"
                font.family: Theme.fontSans
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: Theme.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Plugin info card
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 8
            height: infoCol.height + 16
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            Column {
                id: infoCol
                anchors.centerIn: parent
                width: parent.width - 16
                spacing: 4

                Text {
                    text: installContent.pluginName
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                    width: parent.width
                    elide: Text.ElideRight
                }

                Text {
                    text: installContent.pluginDescription
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textMuted
                    width: parent.width
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    visible: text !== ""
                }

                Row {
                    spacing: 12

                    Text {
                        text: "v" + installContent.pluginVersion
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        color: Theme.textMuted
                    }

                    Text {
                        text: installContent.pluginAuthor
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        color: Theme.textMuted
                        visible: text !== ""
                    }

                    Text {
                        text: installContent.pluginType
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                        color: "#89b4fa"
                    }
                }
            }
        }

        // Buttons
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            // Cancel button
            Rectangle {
                width: 100
                height: 32
                radius: 10
                color: cancelMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    color: Theme.textMuted
                }

                MouseArea {
                    id: cancelMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        console.log("Cancel clicked")
                        installContent.cancel()
                    }
                }
            }

            // Install button
            Rectangle {
                width: 100
                height: 32
                radius: 10
                color: installMa.containsMouse ? "#7c9df0" : "#89b4fa"
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰏗  Install"
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: "#11111b"
                }

                MouseArea {
                    id: installMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        console.log("Install clicked, state=" + installState)
                        if (installState === "confirm") {
                            installContent.startInstall()
                        }
                    }
                }
            }
        }
    }

    // ── Installing State ─────────────────────────────────────────────────
    Column {
        id: installingView
        anchors.centerIn: parent
        spacing: 16
        visible: installContent.installState === "installing"
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Installing " + installContent.pluginName + "…"
            font.family: Theme.fontSans
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Theme.textPrimary
        }

        // Animated progress bar (indeterminate)
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 200
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.08)

            Rectangle {
                id: progressIndicator
                width: parent.width * 0.35
                height: parent.height
                radius: 2
                color: "#89b4fa"

                SequentialAnimation on x {
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: -progressIndicator.width
                        to: progressIndicator.parent.width
                        duration: 1200
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            // Clip the progress bar
            clip: true
        }
    }

    // ── Installed State ──────────────────────────────────────────────────
    Column {
        id: installedView
        anchors.centerIn: parent
        spacing: 12
        visible: installContent.installState === "installed"
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "✓"
            font.pixelSize: 28
            color: "#a6e3a1"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: installContent.pluginName + " installed!"
            font.family: Theme.fontSans
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: "#a6e3a1"
        }
    }

    // ── Error State ──────────────────────────────────────────────────────
    Column {
        id: errorView
        anchors.centerIn: parent
        spacing: 12
        visible: installContent.installState === "error"
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "✗"
            font.pixelSize: 28
            color: Theme.danger
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: installContent.errorMessage || "Installation failed"
            font.family: Theme.fontSans
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Theme.danger
        }
    }
}
