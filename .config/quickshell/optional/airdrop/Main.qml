// optional/airdrop_plugin/Main.qml — AirDrop Widget Plugin
// Type: widget — expone barIcon + expandedPanel para la Dynamic Island
// Se conecta a shellRoot.globalFileDropped para recibir archivos arrastrados.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../style"

Item {
    id: widget

    // Inyectado por PluginManager._finishActivation
    property string pluginId: ""

    // shellRoot se resuelve desde el rootWidget del Loader que carga este widget.
    // PluginManager lo crea con parent=pluginManager, por lo que necesitamos
    // obtener shellRoot a través del rootWidget que Bar.qml inyecta en los Loaders.
    // Como el widget vive en el árbol de PluginManager, usamos una property
    // que Bar.qml puede bindear cuando cargue barIcon/expandedPanel.
    property var shellRoot: null

    // ── Estado ─────────────────────────────────────────────────────────────
    property var droppedFilePaths: []
    property string droppedFileName: ""
    property string droppedFileExt: ""
    property string lsState: "idle"   // idle | scanning | ready | sending | sent | error
    property string statusMessage: ""
    property real progressVal: 0.0
    property bool airdropHovered: false
    property bool isExpanded: false   // controlled by rootWidget via toggleDynamicWidget

    // Dimensiones del panel expandido
    readonly property int expandedWidth: 360
    readonly property int expandedHeight: 320

    // ── Rutas a los scripts (relativas al plugin dir) ────────────────────
    readonly property string pluginDir: Quickshell.env("HOME") + "/.config/quickshell/optional/airdrop"

    ListModel { id: deviceModel }

    // ── Conectar a la señal global de archivos ────────────────────────────
    // Bar.qml emite shellRoot.globalFileDropped cuando algo se arrastra a la isla
    // y NO es un plugin (o son múltiples archivos).
    Connections {
        target: widget.shellRoot
        enabled: widget.shellRoot !== null

        function onGlobalFileDropped(paths) {
            widget.handleFileDrop(paths)
        }
    }

    // ── Processes ─────────────────────────────────────────────────────────
    Process {
        id: discoverProc
        command: ["bash", widget.pluginDir + "/localsend/localsend_discover.sh"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var text = line.trim()
                if (text === "") return
                var parts = text.split('\t')
                if (parts.length >= 2) {
                    var ip = parts[1].trim()
                    if (/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip)) {
                        for (var i = 0; i < deviceModel.count; i++) {
                            if (deviceModel.get(i).ip === ip) return
                        }
                        deviceModel.append({ alias: parts[0].trim(), ip: ip })
                    }
                }
            }
        }
        onExited: {
            if (widget.lsState === "scanning") {
                widget.lsState = "ready"
                widget.statusMessage = deviceModel.count > 0
                    ? "Select a device"
                    : "No devices found"
            }
        }
    }

    Process {
        id: sendProc
        property string targetIp: ""
        command: {
            var cmd = ["bash", widget.pluginDir + "/localsend/localsend_send.sh", targetIp]
            for (var i = 0; i < widget.droppedFilePaths.length; i++) {
                cmd.push(widget.droppedFilePaths[i])
            }
            return cmd
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                var text = line.trim()
                if (text.startsWith("PROGRESS:")) {
                    var val = parseFloat(text.substring(9))
                    if (!isNaN(val)) widget.progressVal = val / 100.0
                } else if (text === "REJECTED") {
                    widget.lsState = "error"
                    widget.statusMessage = "Declined by receiver"
                } else if (text === "CANCELLED") {
                    widget.lsState = "error"
                    widget.statusMessage = "Cancelled by receiver"
                }
            }
        }
        onExited: (code) => {
            if (widget.lsState === "idle") return
            if (code === 0) {
                widget.lsState = "sent"
                widget.statusMessage = "File sent!"
                sentResetTimer.start()
            } else {
                if (widget.lsState !== "error" ||
                    (widget.statusMessage !== "Declined by receiver" &&
                     widget.statusMessage !== "Cancelled by receiver")) {
                    widget.lsState = "error"
                    widget.statusMessage = "Transfer failed"
                }
                sentResetTimer.start()
            }
        }
    }

    Timer {
        id: sentResetTimer
        interval: 2500
        onTriggered: widget.reset()
    }

    // ── API pública ────────────────────────────────────────────────────────
    function handleFileDrop(paths) {
        droppedFilePaths = paths
        if (paths.length === 1) {
            droppedFileName = paths[0].split('/').pop()
            droppedFileExt = droppedFileName.split('.').pop().toUpperCase()
        } else {
            droppedFileName = paths.length + " files"
            droppedFileExt = "MULTIPLE"
        }
        deviceModel.clear()
        lsState = "scanning"
        statusMessage = "Scanning for devices…"
        discoverProc.running = false
        discoverProc.running = true
        // Auto-expand the widget in the island
        if (rootWidget && !isExpanded) {
            rootWidget.toggleDynamicWidget(widget)
        }
    }

    function sendTo(ip) {
        lsState = "sending"
        statusMessage = "Sending…"
        sendProc.targetIp = ip
        sendProc.running = false
        sendProc.running = true
    }

    function reset() {
        lsState = "idle"
        droppedFilePaths = []
        droppedFileName = ""
        droppedFileExt = ""
        statusMessage = ""
        progressVal = 0.0
        deviceModel.clear()
        discoverProc.running = false
        sendProc.running = false
    }

    // Referencia al rootWidget (Bar.qml root) — inyectada por el Loader
    property var rootWidget: null

    // ── barIcon ───────────────────────────────────────────────────────────
    // Componente que se inserta en la fila de íconos de la Dynamic Island
    property Component barIcon: Component {
        Item {
            implicitWidth: widget.lsState === "idle" ? 0 : iconRow.implicitWidth
            implicitHeight: 24
            visible: widget.lsState !== "idle"
            opacity: widget.lsState !== "idle" ? 1.0 : 0.0
            clip: true
            Behavior on implicitWidth { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

            // Conectar shellRoot y rootWidget del Loader al widget
            Component.onCompleted: {
                if (shellRoot && widget.shellRoot !== shellRoot) {
                    widget.shellRoot = shellRoot
                }
                if (rootWidget && widget.rootWidget !== rootWidget) {
                    widget.rootWidget = rootWidget
                }
            }

            Row {
                id: iconRow
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    font.family: Theme.fontMono
                    font.pixelSize: 16
                    color: {
                        if (widget.lsState === "sent")    return "#a6e3a1"
                        if (widget.lsState === "error")   return "#f38ba8"
                        if (widget.lsState === "sending") return "#cba6f7"
                        return "#89dceb"
                    }
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (widget.rootWidget) widget.rootWidget.toggleDynamicWidget(widget)
                }
            }
        }
    }

    // ── expandedPanel ─────────────────────────────────────────────────────
    // Componente que se muestra en el panel expandido de la Dynamic Island
    property Component expandedPanel: Component {
        Item {
            // Conectar shellRoot y rootWidget al widget cuando el panel carga
            Component.onCompleted: {
                if (shellRoot && widget.shellRoot !== shellRoot) {
                    widget.shellRoot = shellRoot
                }
                if (rootWidget && widget.rootWidget !== rootWidget) {
                    widget.rootWidget = rootWidget
                }
            }

            Column {
                anchors.fill: parent
                spacing: 0

                // ── Header ────────────────────────────────────────────────
                RowLayout {
                    width: parent.width
                    height: 40
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        radius: 14
                        color: {
                            if (widget.lsState === "sent")    return Qt.rgba(0.2, 0.8, 0.4, 0.2)
                            if (widget.lsState === "error")   return Qt.rgba(0.9, 0.2, 0.2, 0.2)
                            if (widget.lsState === "sending") return Qt.rgba(0.5, 0.4, 0.9, 0.25)
                            return Qt.rgba(0.35, 0.7, 0.9, 0.2)
                        }
                        Behavior on color { ColorAnimation { duration: 300 } }

                        Text {
                            id: headerIcon
                            anchors.centerIn: parent
                            text: {
                                if (widget.lsState === "sent")    return "󰄬"
                                if (widget.lsState === "error")   return "󰅖"
                                if (widget.lsState === "sending") return "󰕒"
                                return ""
                            }
                            font.family: Theme.fontMono; font.pixelSize: 14
                            color: {
                                if (widget.lsState === "sent")    return "#a6e3a1"
                                if (widget.lsState === "error")   return "#f38ba8"
                                if (widget.lsState === "sending") return "#cba6f7"
                                return "#89dceb"
                            }
                            Behavior on color { ColorAnimation { duration: 300 } }
                            SequentialAnimation {
                                running: widget.lsState === "scanning"
                                loops: Animation.Infinite
                                NumberAnimation { target: headerIcon; property: "rotation"; from: 0; to: 360; duration: 1200 }
                            }
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: widget.droppedFileName || "AirDrop"
                            font.family: Theme.fontMono; font.pixelSize: 12
                            font.weight: Font.Bold; color: Theme.textPrimary
                            elide: Text.ElideMiddle
                        }
                        Text {
                            text: {
                                if (widget.lsState === "idle" && !widget.droppedFileName) return "Drag files onto the island"
                                if (widget.statusMessage) return widget.statusMessage
                                return widget.droppedFileExt + " file"
                            }
                            font.family: Theme.fontMono; font.pixelSize: 10
                            color: Theme.textPrimary; opacity: 0.5
                        }
                    }

                    // Minimize button
                    Rectangle {
                        Layout.preferredWidth: 24; Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: 12
                        color: minHov.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent; text: ""
                            font.family: Theme.fontMono; font.pixelSize: 12
                            color: Theme.textPrimary; opacity: 0.6
                        }
                        MouseArea {
                            id: minHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (widget.rootWidget) widget.rootWidget.toggleDynamicWidget(widget)
                            }
                        }
                    }

                    // Close button
                    Rectangle {
                        Layout.preferredWidth: 24; Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: 12
                        color: closeHov.containsMouse ? Qt.rgba(1,1,1,0.1) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent; text: ""
                            font.family: Theme.fontMono; font.pixelSize: 12
                            color: Theme.textPrimary; opacity: 0.6
                        }
                        MouseArea {
                            id: closeHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                widget.reset()
                                if (widget.rootWidget) widget.rootWidget.toggleDynamicWidget(widget)
                            }
                        }
                    }
                }

                // Divider
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

                // ── Body ──────────────────────────────────────────────────
                Item {
                    width: parent.width
                    height: parent.height - 41

                    // Scanning spinner
                    Column {
                        anchors.centerIn: parent; spacing: 12
                        visible: widget.lsState === "scanning" && deviceModel.count === 0

                        Rectangle {
                            width: 36; height: 36; radius: 18
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Qt.rgba(0.35, 0.7, 0.9, 0.15)
                            border.width: 2; border.color: Qt.rgba(0.35, 0.7, 0.9, 0.3)
                            Text {
                                id: scanIcon; anchors.centerIn: parent; text: "󰍉"
                                font.family: Theme.fontMono; font.pixelSize: 16; color: "#89dceb"
                                SequentialAnimation {
                                    running: widget.lsState === "scanning"; loops: Animation.Infinite
                                    NumberAnimation { target: scanIcon; property: "rotation"; from: 0; to: 360; duration: 1500 }
                                }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Scanning network…"; font.family: Theme.fontMono
                            font.pixelSize: 11; color: Theme.textPrimary; opacity: 0.5
                        }
                    }

                    // Sending
                    Column {
                        anchors.centerIn: parent; spacing: 12
                        visible: widget.lsState === "sending"

                        Rectangle {
                            width: 36; height: 36; radius: 18
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Qt.rgba(0.5, 0.4, 0.9, 0.15)
                            border.width: 2; border.color: Qt.rgba(0.5, 0.4, 0.9, 0.3)
                            Text {
                                anchors.centerIn: parent; text: "󰕒"
                                font.family: Theme.fontMono; font.pixelSize: 16; color: "#cba6f7"
                                SequentialAnimation on opacity {
                                    running: widget.lsState === "sending"; loops: Animation.Infinite
                                    NumberAnimation { from: 1.0; to: 0.3; duration: 800 }
                                    NumberAnimation { from: 0.3; to: 1.0; duration: 800 }
                                }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Sending " + widget.droppedFileName + "…"
                            font.family: Theme.fontMono; font.pixelSize: 11
                            color: Theme.textPrimary; opacity: 0.5
                            elide: Text.ElideMiddle; width: 200
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 140; height: 4; radius: 2
                            color: Qt.rgba(1,1,1,0.1); clip: true
                            Rectangle {
                                height: parent.height; radius: 2; color: "#cba6f7"
                                width: parent.width * Math.max(0, Math.min(1, widget.progressVal))
                                Behavior on width { NumberAnimation { duration: 100 } }
                            }
                        }
                    }

                    // Sent / Error
                    Column {
                        anchors.centerIn: parent; spacing: 10
                        visible: widget.lsState === "sent" || widget.lsState === "error"

                        Rectangle {
                            width: 36; height: 36; radius: 18
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: widget.lsState === "sent" ? Qt.rgba(0.2,0.8,0.4,0.15) : Qt.rgba(0.9,0.2,0.2,0.15)
                            border.width: 2
                            border.color: widget.lsState === "sent" ? Qt.rgba(0.2,0.8,0.4,0.3) : Qt.rgba(0.9,0.2,0.2,0.3)
                            Text {
                                anchors.centerIn: parent
                                text: widget.lsState === "sent" ? "󰄬" : "󰅖"
                                font.family: Theme.fontMono; font.pixelSize: 16
                                color: widget.lsState === "sent" ? "#a6e3a1" : "#f38ba8"
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: widget.statusMessage
                            font.family: Theme.fontMono; font.pixelSize: 12; font.weight: Font.Medium
                            color: widget.lsState === "sent" ? "#a6e3a1" : "#f38ba8"
                        }
                    }

                    // Device list (ready + scanning with results)
                    ListView {
                        id: deviceList
                        anchors.fill: parent; anchors.topMargin: 6
                        clip: true
                        visible: widget.lsState === "ready" || (widget.lsState === "scanning" && deviceModel.count > 0)
                        model: deviceModel; spacing: 5

                        Text {
                            anchors.centerIn: parent
                            visible: widget.lsState === "ready" && deviceModel.count === 0
                            text: "No devices found"
                            font.family: Theme.fontMono; font.pixelSize: 11
                            color: Theme.textPrimary; opacity: 0.4
                        }

                        delegate: Rectangle {
                            width: deviceList.width; height: 42; radius: 10
                            color: devHov.containsMouse ? Qt.rgba(0.35,0.7,0.9,0.12) : Qt.rgba(1,1,1,0.04)
                            border.width: 1
                            border.color: devHov.containsMouse ? Qt.rgba(0.35,0.7,0.9,0.25) : Qt.rgba(1,1,1,0.06)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 26; Layout.preferredHeight: 26
                                    Layout.alignment: Qt.AlignVCenter; radius: 13
                                    color: Qt.rgba(0.35, 0.7, 0.9, 0.15)
                                    Text { anchors.centerIn: parent; text: "󰐻"; font.family: Theme.fontMono; font.pixelSize: 13; color: "#89dceb" }
                                }

                                Column {
                                    Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; spacing: 1
                                    Text { text: model.alias; font.family: Theme.fontMono; font.pixelSize: 11; font.weight: Font.Bold; color: Theme.textPrimary }
                                    Text { text: model.ip; font.family: Theme.fontMono; font.pixelSize: 9; color: Theme.textPrimary; opacity: 0.4 }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignVCenter; text: "󰁔"
                                    font.family: Theme.fontMono; font.pixelSize: 14; color: "#89dceb"
                                    opacity: devHov.containsMouse ? 1.0 : 0.3
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }
                            }

                            MouseArea {
                                id: devHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: widget.lsState === "ready"
                                onClicked: widget.sendTo(model.ip)
                            }
                        }
                    }

                    // Rescan button
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottomMargin: 4
                        width: 90; height: 24; radius: 12
                        visible: widget.lsState === "ready"
                        color: rescanHov.containsMouse ? Qt.rgba(1,1,1,0.08) : Qt.rgba(1,1,1,0.04)
                        border.width: 1; border.color: Qt.rgba(1,1,1,0.08)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row { anchors.centerIn: parent; spacing: 5
                            Text { text: "󰑐"; font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.textPrimary; opacity: 0.6 }
                            Text { text: "Rescan"; font.family: Theme.fontMono; font.pixelSize: 9; color: Theme.textPrimary; opacity: 0.6 }
                        }

                        MouseArea {
                            id: rescanHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                deviceModel.clear()
                                widget.lsState = "scanning"
                                widget.statusMessage = "Scanning for devices…"
                                discoverProc.running = false
                                discoverProc.running = true
                            }
                        }
                    }
                }
            }
        }
    }
}
