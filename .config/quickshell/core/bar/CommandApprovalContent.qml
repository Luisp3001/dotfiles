// core/bar/CommandApprovalContent.qml — Minerva command approval UI for the Dynamic Island
// Shows command info + Execute/Cancel buttons when Minerva needs permission.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../style"

Item {
    id: approvalContent

    // ── Interface ────────────────────────────────────────────────────────
    property var rootWidget
    property var shellRoot: null

    // Command metadata (set from Bar.qml / shell.qml)
    property string pendingCommand: ""
    property string pendingReason: ""
    property bool isSudo: false

    // State: confirm | running | success | error
    property string approvalState: "confirm"
    onApprovalStateChanged: {
        if (shellRoot) {
            shellRoot.commandApprovalRunning = (approvalState === "running")
        }
    }
    property string errorMessage: ""
    property string resultOutput: ""

    // Height adapts to state
    property int preferredHeight: {
        if (approvalState === "confirm") return 180
        if (approvalState === "running") return 140
        return 130 // success / error
    }

    // ── Set command data ─────────────────────────────────────────────────
    function setCommand(cmd, reason, sudo) {
        pendingCommand = cmd
        pendingReason = reason || (sudo ? "Este comando requiere permisos de administrador" : "Comando potencialmente destructivo")
        isSudo = sudo
        approvalState = "confirm"
        errorMessage = ""
        resultOutput = ""
    }

    // ── Reset ────────────────────────────────────────────────────────────
    function reset() {
        approvalState = "confirm"
        pendingCommand = ""
        pendingReason = ""
        isSudo = false
        errorMessage = ""
        resultOutput = ""
    }

    // ── Auto-close timer ─────────────────────────────────────────────────
    Timer {
        id: autoCloseTimer
        interval: 2500
        onTriggered: {
            if (shellRoot) {
                shellRoot.commandApprovalOpen = false
            }
            approvalContent.reset()
        }
    }

    // ── React to shellRoot state changes ──────────────────────────────────
    Connections {
        target: approvalContent.shellRoot
        function onCommandApprovalOpenChanged() {
            if (approvalContent.shellRoot && approvalContent.shellRoot.commandApprovalOpen) {
                approvalContent.setCommand(
                    approvalContent.shellRoot.minervaPendingCmd,
                    approvalContent.shellRoot.minervaPendingReason,
                    approvalContent.shellRoot.minervaPendingIsSudo
                )
            }
        }
        function onMinervaCommandResultReceived() {
            if (approvalContent.shellRoot) {
                approvalContent.onCommandResult(
                    approvalContent.shellRoot.minervaCommandSuccess,
                    approvalContent.shellRoot.minervaCommandOutput
                )
            }
        }
    }

    // ── Approve action ───────────────────────────────────────────────────
    function approve() {
        if (pendingCommand === "") return
        approvalState = "running"

        // Find the Minerva plugin and call its approve function
        if (shellRoot && shellRoot.pluginManager) {
            var plugins = shellRoot.pluginManager.activeWidgets
            for (var i = 0; i < plugins.length; i++) {
                if (plugins[i].pluginId === "com.luisp.minerva") {
                    if (isSudo) {
                        plugins[i].sudoRun(pendingCommand)
                    } else {
                        plugins[i].confirmRun(pendingCommand)
                    }

                    // Also update the chat model command card status
                    var model = plugins[i].msgModel
                    for (var j = model.count - 1; j >= 0; j--) {
                        var item = model.get(j)
                        if (item.role === "command" && item.cmdStatus === "pending" && item.content === pendingCommand) {
                            model.setProperty(j, "cmdStatus", "running")
                            break
                        }
                    }
                    break
                }
            }
        }
    }

    // ── Reject action ────────────────────────────────────────────────────
    function reject() {
        if (shellRoot) {
            shellRoot.commandApprovalOpen = false
        }

        // Mark the command card as cancelled in the chat model
        if (shellRoot && shellRoot.pluginManager) {
            var plugins = shellRoot.pluginManager.activeWidgets
            for (var i = 0; i < plugins.length; i++) {
                if (plugins[i].pluginId === "com.luisp.minerva") {
                    var model = plugins[i].msgModel
                    for (var j = model.count - 1; j >= 0; j--) {
                        var item = model.get(j)
                        if (item.role === "command" && item.cmdStatus === "pending" && item.content === pendingCommand) {
                            model.setProperty(j, "cmdStatus", "cancelled")
                            break
                        }
                    }
                    // Dismiss the confirm dialog in the plugin too
                    plugins[i].showConfirm = false
                    break
                }
            }
        }
        reset()
    }

    // ── Handle command result ────────────────────────────────────────────
    function onCommandResult(success, output) {
        if (approvalState !== "running") return
        approvalState = success ? "success" : "error"
        resultOutput = output || ""
        if (!success) errorMessage = output || "El comando falló"
        autoCloseTimer.start()
    }

    // ══════════════════════════════════════════════════════════════════════
    // ── Visual UI ────────────────────────────────────────────────────────
    // ══════════════════════════════════════════════════════════════════════

    // ── Confirm State ────────────────────────────────────────────────────
    Column {
        id: confirmView
        anchors.fill: parent
        anchors.margins: 4
        spacing: 8
        visible: approvalContent.approvalState === "confirm"
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        // Header
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            Text {
                text: approvalContent.isSudo ? "󰌞" : "󰀦"
                font.family: Theme.fontMono
                font.pixelSize: 20
                color: Theme.warning
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: approvalContent.isSudo ? "Permisos elevados" : "¿Confirmar acción?"
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.warning
                }
                Text {
                    text: "Minerva"
                    font.family: Theme.fontSans
                    font.pixelSize: 10
                    color: Theme.textMuted
                }
            }
        }

        // Reason
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 8
            text: approvalContent.pendingReason
            font.family: Theme.fontSans
            font.pixelSize: 11
            color: Theme.textMuted
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // Command card
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 8
            height: cmdText.implicitHeight + 14
            radius: 10
            color: Qt.rgba(0, 0, 0, 0.4)
            border.width: 1
            border.color: Qt.rgba(0.95, 0.65, 0.2, 0.25)

            Text {
                id: cmdText
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 10
                }
                text: "$ " + approvalContent.pendingCommand
                font.family: Theme.fontMono
                font.pixelSize: 11
                color: Theme.warning
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
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
                color: rejectMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "Cancelar"
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    color: Theme.textMuted
                }

                MouseArea {
                    id: rejectMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: approvalContent.reject()
                }
            }

            // Execute button
            Rectangle {
                width: approvalContent.isSudo ? 140 : 110
                height: 32
                radius: 10
                color: approveMa.containsMouse ? Qt.rgba(0.75, 0.45, 0.08, 0.6) : Qt.rgba(0.5, 0.28, 0.04, 0.45)
                border.width: 1
                border.color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.75)
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: "󰄬"
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        color: Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: approvalContent.isSudo ? "Ejecutar (pkexec)" : "Ejecutar"
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: approveMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (approvalContent.approvalState === "confirm") {
                            approvalContent.approve()
                        }
                    }
                }
            }
        }
    }

    // ── Running State ────────────────────────────────────────────────────
    Column {
        id: runningView
        anchors.centerIn: parent
        spacing: 16
        visible: approvalContent.approvalState === "running"
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Ejecutando comando…"
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
                color: Theme.warning

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

            clip: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "$ " + approvalContent.pendingCommand
            font.family: Theme.fontMono
            font.pixelSize: 10
            color: Theme.textMuted
            width: parent.parent.width - 40
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    // ── Success State ────────────────────────────────────────────────────
    Column {
        id: successView
        anchors.centerIn: parent
        spacing: 12
        visible: approvalContent.approvalState === "success"
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
            text: "Comando ejecutado"
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
        visible: approvalContent.approvalState === "error"
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
            text: approvalContent.errorMessage || "El comando falló"
            font.family: Theme.fontSans
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Theme.danger
            width: parent.parent.width - 40
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }
    }
}
