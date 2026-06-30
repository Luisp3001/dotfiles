// optional/ollama_ai/Main.qml — Plugin raíz del Asistente Ollama AI
// Gestiona el proceso backend Python y el estado global del plugin.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../style"

Item {
    id: widget

    // ── Interfaz estándar del plugin ──────────────────────────────────────
    property string pluginId: "com.luisp.ollama_ai"
    property var    shellRoot:  null
    property var    rootWidget: null
    property bool   isCenterTabActive: false
    property string tabIcon: "󱜚"

    readonly property int expandedWidth:  520
    readonly property int expandedHeight: 560

    // ── Estado del backend ────────────────────────────────────────────────
    property bool   backendReady:  false
    property bool   isThinking:    false
    property string lastAISnippet: "Minerva"
    readonly property string modelName: "Gemma4:e4b"

    // ── Estado de la UI persistente ───────────────────────────────────────
    property var    conversationHistory: []
    property string currentUserMsg: ""
    property int    streamingIdx: -1
    property string streamingRaw: ""
    property string pendingCmd: ""
    property bool   pendingIsSudo: false
    property string pendingReason: ""
    property bool   showConfirm: false

    ListModel { id: globalMsgModel }
    property alias msgModel: globalMsgModel


    // ── Señal reenviada a ChatWidget ──────────────────────────────────────
    signal backendMessage(var msg)

    // ── Ruta al backend Python ────────────────────────────────────────────
    readonly property string pluginDir:
        Quickshell.env("HOME") + "/.config/quickshell/optional/ollama_ai"

    // ── Proceso backend persistente ───────────────────────────────────────
    Process {
        id: backendProc
        command: [widget.pluginDir + "/venv/bin/python3", "-u", widget.pluginDir + "/backend.py"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var trimmed = line.trim()
                if (!trimmed) return
                try {
                    widget.onBackendLine(JSON.parse(trimmed))
                } catch (_) {}
            }
        }

        onExited: function(code) {
            widget.backendReady = false
            widget.isThinking   = false
            widget.backendMessage({ type: "error",
                message: "Backend terminó (código " + code + "). Reinicia Quickshell." })
        }
    }

    // ── Comunicación con el backend (HTTP POST) ───────────────────────────
    function sendToBackend(obj) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:11435", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status !== 200) {
                console.error("Ollama AI Backend HTTP error: " + xhr.status)
            }
        }
        xhr.send(JSON.stringify(obj))
    }

    function onBackendLine(msg) {
        // Actualizar estado del widget
        switch (msg.type) {
            case "ready":
                backendReady = true
                break
            case "token":
                isThinking = true
                break
            case "done":
                isThinking = false
                // Extraer snippet visible (sin líneas TOOL_CALL)
                if (msg.full_response) {
                    var lines = msg.full_response.split("\n")
                    for (var i = 0; i < lines.length; i++) {
                        var l = lines[i].trim()
                        if (l && !l.startsWith("TOOL_CALL:")) {
                            lastAISnippet = l.length > 40 ? l.substring(0, 40) + "…" : l
                            break
                        }
                    }
                }
                break
            case "error":
            case "confirm_required":
            case "sudo_required":
            case "run_command":
                isThinking = false
                break
        }
        // Reenviar a ChatWidget
        widget.backendMessage(msg)
    }

    function sendChat(message, history) {
        isThinking = true
        sendToBackend({ type: "chat", message: message, history: history })
    }

    function confirmRun(cmd) { sendToBackend({ type: "run_confirmed", command: cmd }) }
    function cancelRun()     { sendToBackend({ type: "cancel" }) }
    function sudoRun(cmd)    { sendToBackend({ type: "run_sudo",      command: cmd }) }

    // ── barIcon ───────────────────────────────────────────────────────────
    // Icono en la barra derecha: pulsa cuando la IA está pensando,
    // rojo si el backend no está listo.
    property Component barIcon: Component {
        Item {
            implicitWidth: 26
            implicitHeight: 24

            width:   widget.isCenterTabActive ? 0            : implicitWidth
            opacity: widget.isCenterTabActive ? 0.0          : 1.0
            visible: opacity > 0
            clip:    true

            Behavior on width   { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

            Component.onCompleted: {
                if (shellRoot  && widget.shellRoot  !== shellRoot)  widget.shellRoot  = shellRoot
                if (rootWidget && widget.rootWidget !== rootWidget) widget.rootWidget = rootWidget
            }

            Text {
                id: aiBarIcon
                anchors.centerIn: parent
                text: "󱜚"
                font.family: Theme.fontMono
                font.pixelSize: 16
                color: !widget.backendReady ? Theme.danger
                     : widget.isThinking   ? Theme.accent
                     :                       Theme.textMuted
                Behavior on color { ColorAnimation { duration: 300 } }

                SequentialAnimation on opacity {
                    running: widget.isThinking
                    loops:   Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutSine }
                    onStopped: aiBarIcon.opacity = 1.0
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked:  { if (widget.rootWidget) widget.rootWidget.toggleDynamicWidget(widget) }
                onEntered:  aiBarIcon.color = Theme.accent
                onExited:   aiBarIcon.color = !widget.backendReady ? Theme.danger
                                            : widget.isThinking   ? Theme.accent
                                            :                        Theme.textMuted
            }
        }
    }

    // ── centerWidget ──────────────────────────────────────────────────────
    // Pastilla central: muestra estado o último snippet de la IA.
    property Component centerWidget: Component {
        Item {
            implicitWidth: cwRow.implicitWidth + 8
            implicitHeight: 24

            Row {
                id: cwRow
                anchors.centerIn: parent
                spacing: 7

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󱜚"
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                    color: widget.isThinking ? Theme.accent : Theme.textMuted

                    SequentialAnimation on opacity {
                        running: widget.isThinking
                        loops:   Animation.Infinite
                        NumberAnimation { to: 0.15; duration: 700 }
                        NumberAnimation { to: 1.0;  duration: 700 }
                        onStopped: opacity = 1.0
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: widget.isThinking    ? "Pensando…"
                        : !widget.backendReady ? "Iniciando Minerva…"
                        : "Minerva"
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight:    Font.DemiBold
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 190)
                }
            }
        }
    }

    // ── expandedPanel ─────────────────────────────────────────────────────
    // Panel expandido: instancia ChatWidget pasando referencia a este widget.
    property Component expandedPanel: Component {
        Item {
            Component.onCompleted: {
                if (shellRoot  && widget.shellRoot  !== shellRoot)  widget.shellRoot  = shellRoot
                if (rootWidget && widget.rootWidget !== rootWidget) widget.rootWidget = rootWidget
            }

            ChatWidget {
                anchors.fill: parent
                aiWidget: widget
            }
        }
    }
}
