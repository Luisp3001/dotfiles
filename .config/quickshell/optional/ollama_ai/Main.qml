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

    readonly property int expandedWidth:  600
    readonly property int expandedHeight: 560

    // ── Configuración de IA ───────────────────────────────────────────────
    property string aiProvider: "Ollama"
    property string geminiApiKey: ""
    property string geminiModel: "gemini-2.5-flash"
    property string aiModel: "qwen3.5:9b"
    property string aiTemperature: "0.7"
    property string aiNumCtx: "8192"
    property bool   aiThinking: false

    property var settingsConfig: [
        { id: "aiProvider", name: "Proveedor de IA (Ollama / Gemini)", type: "string", defaultValue: "Ollama" },
        { id: "geminiApiKey", name: "API Key de Gemini", type: "string", defaultValue: "" },
        { id: "geminiModel", name: "Modelo de Gemini", type: "string", defaultValue: "gemini-2.5-flash" },
        { id: "aiModel", name: "Modelo de Ollama", type: "string", defaultValue: "qwen3.5:9b" },
        { id: "aiTemperature", name: "Temperatura (0.0 - 1.0)", type: "string", defaultValue: "0.7" },
        { id: "aiNumCtx", name: "Contexto (num_ctx)", type: "string", defaultValue: "8192" },
        { id: "aiThinking", name: "Activar razonamiento (Thinking)", type: "bool", defaultValue: false }
    ]

    Component.onCompleted: {
        if (parent && parent.getSetting) {
            aiProvider = parent.getSetting(pluginId, "aiProvider", "Ollama")
            geminiApiKey = parent.getSetting(pluginId, "geminiApiKey", "")
            geminiModel = parent.getSetting(pluginId, "geminiModel", "gemini-2.5-flash")
            aiModel = parent.getSetting(pluginId, "aiModel", "qwen3.5:9b")
            aiTemperature = parent.getSetting(pluginId, "aiTemperature", "0.7")
            aiNumCtx = parent.getSetting(pluginId, "aiNumCtx", "8192")
            aiThinking = parent.getSetting(pluginId, "aiThinking", false)
        }
    }

    Connections {
        target: widget.parent && widget.parent.settingChanged ? widget.parent : null
        function onSettingChanged(id, key, value) {
            if (id === widget.pluginId) {
                if (key === "aiProvider") widget.aiProvider = value
                else if (key === "geminiApiKey") widget.geminiApiKey = value
                else if (key === "geminiModel") widget.geminiModel = value
                else if (key === "aiModel") widget.aiModel = value
                else if (key === "aiTemperature") widget.aiTemperature = value
                else if (key === "aiNumCtx") widget.aiNumCtx = value
                else if (key === "aiThinking") widget.aiThinking = value
            }
        }
    }

    // ── Estado del backend ────────────────────────────────────────────────
    property bool   backendReady:  false
    property bool   isThinking:    false
    property string lastAISnippet: "Minerva"
    property string modelName: aiModel

    // ── Estado de la UI persistente ───────────────────────────────────────
    property var    conversationHistory: []
    property string currentUserMsg: ""
    property int    streamingIdx: -1
    property string streamingRaw: ""
    property string pendingCmd: ""
    property bool   pendingIsSudo: false
    property string pendingReason: ""
    property bool   showConfirm: false
    property bool   isRecording: false
    property bool   isTranscribing: false

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
        command: [widget.pluginDir + "/.venv/bin/python3", "-u", widget.pluginDir + "/backend.py"]
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
            case "voice_recording_started":
                isRecording = true
                break
            case "voice_recording_stopped":
                isRecording = false
                break
            case "voice_transcribing":
                isTranscribing = true
                break
            case "voice_recognized":
                isRecording = false
                isTranscribing = false
                if (msg.text) {
                    // Simular que el usuario escribió el texto
                    currentUserMsg = msg.text
                    globalMsgModel.append({
                        role: "user", content: msg.text, command: "", cmdStatus: "",
                        needsConfirm: false, needsSudo: false, isSystem: false
                    })
                    sendChat(msg.text, conversationHistory.slice())
                }
                break
        }
        // Reenviar a ChatWidget
        widget.backendMessage(msg)
    }

    function sendChat(message, history) {
        if (isRecording) { toggleVoice() }
        isThinking = true
        sendToBackend({ 
            type: "chat", 
            message: message, 
            history: history,
            settings: {
                provider: widget.aiProvider,
                gemini_api_key: widget.geminiApiKey,
                gemini_model: widget.geminiModel,
                model: widget.aiModel,
                temperature: widget.aiTemperature,
                num_ctx: widget.aiNumCtx,
                thinking: widget.aiThinking
            }
        })
    }

    function confirmRun(cmd) { sendToBackend({ type: "run_confirmed", command: cmd }) }
    function cancelRun()     { sendToBackend({ type: "cancel" }) }
    function sudoRun(cmd)    { sendToBackend({ type: "run_sudo",      command: cmd }) }
    function toggleVoice()   { sendToBackend({ type: "toggle_voice" }) }
    function stopTTS()       { sendToBackend({ type: "stop_tts" }) }

    // ── IPC Handler (qs ipc call minerva) ─────────────────────────────────
    IpcHandler {
        target: "minerva"
        function toggle_voice(): string {
            widget.toggleVoice()
            return widget.isRecording ? "Grabación de voz detenida" : "Iniciando grabación de voz..."
        }
        function stop_tts(): string {
            widget.stopTTS()
            return "Voz detenida"
        }
    }

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
