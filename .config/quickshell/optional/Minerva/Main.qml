// optional/Minerva/Main.qml — Plugin raíz del Asistente Minerva
// Gestiona el proceso backend Python y el estado global del plugin.
import QtQuick
import Quickshell
import Quickshell.Io
import "../../style"

Item {
    id: widget

    // ── Interfaz estándar del plugin ──────────────────────────────────────
    property string pluginId: "com.luisp.minerva"
    property var    shellRoot:  null
    property var    rootWidget: null
    property bool   isCenterTabActive: false
    property string tabIcon: "󱜚"

    property bool showOnlyOrb: false  // kept for legacy compat, no longer used
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
    property bool   isSpeaking:    false
    property bool   hasPendingTasks: false
    property bool   hasUrgentTasks: false
    property string taskUrgency: "low"
    property bool   showPendingOrb: false
    property string lastAISnippet: "Minerva"
    property string modelName: aiProvider === "Gemini" ? geminiModel : aiModel
    
    Timer {
        id: pendingOrbTimer
        interval: 20000 // Mostrar el orbe central por 20 segundos
        onTriggered: {
            widget.showPendingOrb = false
            widget._updateMinervaState()
        }
    }

    // ── Estado de la UI persistente ───────────────────────────────────────
    property var    conversationHistory: []
    property string currentUserMsg: ""
    property int    streamingIdx: -1
    property string streamingRaw: ""
    property string pendingCmd: ""
    property string pendingJobId: ""
    property bool   pendingIsSudo: false
    property string pendingReason: ""
    property bool   showConfirm: false
    property bool   isRecording: false
    property bool   isTranscribing: false
    property string pendingImage: ""

    ListModel { id: globalMsgModel }
    property alias msgModel: globalMsgModel


    // ── Señal reenviada a ChatWidget ──────────────────────────────────────
    signal backendMessage(var msg)

    // ── Ruta al backend Python ────────────────────────────────────────────
    readonly property string pluginDir:
        Quickshell.env("HOME") + "/.config/quickshell/optional/Minerva"

    // ── Proceso backend persistente ───────────────────────────────────────
    Process {
        id: backendProc
        command: [widget.pluginDir + "/.venv/bin/python3", "-u", widget.pluginDir + "/main.py"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var trimmed = line.trim()
                if (!trimmed) return
                try {
                    var parsed = JSON.parse(trimmed)
                    Qt.callLater(function() {
                        widget.onBackendLine(parsed)
                    })
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

    // ── Proceso de selección de imagen ────────────────────────────────────
    Process {
        id: imageDialogProc
        command: ["zenity", "--file-selection", "--title=Selecciona una imagen", "--file-filter=*.png *.jpg *.jpeg *.webp"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var path = line.trim()
                if (path) {
                    widget.pendingImage = path
                }
            }
        }
    }

    function selectImage() {
        imageDialogProc.running = true
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

    // ── Helpers para actualizar estado global de voz ───────────────────────
    function _updateMinervaState() {
        if (!widget.shellRoot) return
        var active = widget.isRecording || widget.isTranscribing || widget.isThinking || widget.isSpeaking || widget.showPendingOrb
        widget.shellRoot.minervaActive = active
        if (widget.isRecording)         widget.shellRoot.minervaState = "recording"
        else if (widget.isTranscribing) widget.shellRoot.minervaState = "transcribing"
        else if (widget.isThinking)     widget.shellRoot.minervaState = "thinking"
        else if (widget.isSpeaking)     widget.shellRoot.minervaState = "speaking"
        else if (widget.showPendingOrb) {
            if (widget.hasUrgentTasks || widget.taskUrgency === "urgent")
                widget.shellRoot.minervaState = "urgent_task"
            else if (widget.taskUrgency === "medium")
                widget.shellRoot.minervaState = "pending_task_medium"
            else
                widget.shellRoot.minervaState = "pending_task_low"
        }
        else widget.shellRoot.minervaState = "idle"
    }

    function onBackendLine(msg) {
        // Actualizar estado del widget
        switch (msg.type) {
            case "tasks_pending":
                hasPendingTasks = true
                taskUrgency = msg.urgency ? msg.urgency : (msg.urgent ? "urgent" : "low")
                hasUrgentTasks = (taskUrgency === "urgent")
                showPendingOrb = true
                pendingOrbTimer.restart()
                _updateMinervaState()
                break
            case "tasks_cleared":
                hasPendingTasks = false
                hasUrgentTasks = false
                taskUrgency = ""
                showPendingOrb = false
                pendingOrbTimer.stop()
                _updateMinervaState()
                break
            case "ready":
                backendReady = true
                break
            case "token":
                isThinking = true
                _updateMinervaState()
                // Acumular token en globalMsgModel (por si ChatWidget no está abierto)
                if (streamingIdx === -1) {
                    globalMsgModel.append({
                        role: "ai", content: "", command: "", cmdStatus: "",
                        needsConfirm: false, needsSudo: false, isSystem: false
                    })
                    streamingIdx = globalMsgModel.count - 1
                    streamingRaw = ""
                }
                streamingRaw += (msg.content || "")
                globalMsgModel.setProperty(streamingIdx, "content", streamingRaw)
                break
            case "done":
                isThinking = false
                _updateMinervaState()
                // Guardar en historial si no lo hizo ChatWidget (panel cerrado)
                if (streamingIdx >= 0) {
                    conversationHistory.push(
                        { role: "user",      content: currentUserMsg },
                        { role: "assistant", content: msg.full_response || streamingRaw }
                    )
                    streamingIdx = -1
                    streamingRaw = ""
                }
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
                if (streamingIdx >= 0) {
                    streamingIdx = -1
                    streamingRaw = ""
                }
                isThinking = false
                _updateMinervaState()
                break
            case "run_command":
                isThinking = false
                _updateMinervaState()
                break
            case "confirm_required":
            case "sudo_required":
                isThinking = false
                _updateMinervaState()
                // Expandir la isla si estaba cerrada para mostrar el overlay de confirmación del chat
                if (widget.shellRoot && widget.shellRoot.activeDynamicWidget !== widget) {
                    widget.shellRoot.activeDynamicWidget = widget
                }
                break
            case "command_result":
                // Resultado manejado internamente por ChatWidget
                break
            case "wake_word_detected":
                if (!isRecording) {
                    toggleVoice()
                    // Opción A: cerrar el panel expandido al activar voz
                    if (widget.shellRoot && widget.shellRoot.activeDynamicWidget === widget) {
                        if (widget.rootWidget) widget.rootWidget.toggleDynamicWidget(widget)
                    }
                }
                break
            case "silence_detected":
                if (isRecording) {
                    toggleVoice()
                }
                break
            case "voice_recording_started":
                isRecording = true
                _updateMinervaState()
                break
            case "voice_recording_stopped":
                isRecording = false
                _updateMinervaState()
                break
            case "voice_transcribing":
                isTranscribing = true
                _updateMinervaState()
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
                } else {
                    _updateMinervaState()
                }
                break
            case "voice_speaking_started":
                isSpeaking = true
                _updateMinervaState()
                break
            case "voice_speaking_stopped":
                isSpeaking = false
                // Resetear métricas de audio al dejar de hablar
                if (widget.shellRoot) {
                    widget.shellRoot.audioRms   = 0.0
                    widget.shellRoot.audioBand0 = 0.0
                    widget.shellRoot.audioBand1 = 0.0
                    widget.shellRoot.audioBand2 = 0.0
                    widget.shellRoot.audioBand3 = 0.0
                }
                _updateMinervaState()
                break
            case "audio_data":
                // Métricas de audio en tiempo real → SiriOrb shader
                if (widget.shellRoot) {
                    widget.shellRoot.audioRms   = msg.rms   || 0.0
                    widget.shellRoot.audioBand0 = msg.band0 || 0.0
                    widget.shellRoot.audioBand1 = msg.band1 || 0.0
                    widget.shellRoot.audioBand2 = msg.band2 || 0.0
                    widget.shellRoot.audioBand3 = msg.band3 || 0.0
                }
                break
        }
        // Reenviar a ChatWidget
        widget.backendMessage(msg)
    }

    function sendChat(message, history) {
        if (isRecording) { toggleVoice() }
        isThinking = true
        _updateMinervaState()
        sendToBackend({ 
            type: "chat", 
            message: message, 
            history: history,
            image: widget.pendingImage,
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
        widget.pendingImage = ""
    }

    function confirmRun(cmd, jobId) { sendToBackend({ type: "run_confirmed", job_id: jobId || "", command: cmd }) }
    function cancelRun()            { sendToBackend({ type: "cancel" }) }
    function sudoRun(cmd, jobId)    { sendToBackend({ type: "run_sudo",      job_id: jobId || "", command: cmd }) }
    function cancelJob(jobId)       { sendToBackend({ type: "job_cancelled", job_id: jobId || "" }) }
    function toggleVoice()          { sendToBackend({ type: "toggle_voice" }) }
    function stopTTS()              { sendToBackend({ type: "stop_tts" }) }

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
                text: widget.isRecording ? "󰍬" : (widget.hasPendingTasks ? "󱜚" : "󱜚")
                font.family: Theme.fontMono
                font.pixelSize: 16
                color: !widget.backendReady ? Theme.danger
                     : widget.isRecording ? Theme.danger
                     : widget.isThinking  ? Theme.accent
                     : widget.hasPendingTasks ? Theme.warning
                     :                      Theme.textMuted
                Behavior on color { ColorAnimation { duration: 300 } }

                SequentialAnimation on opacity {
                    running: widget.isThinking || widget.isRecording || (widget.hasPendingTasks && !widget.isThinking && !widget.isRecording)
                    loops:   Animation.Infinite
                    NumberAnimation { to: widget.hasPendingTasks && !widget.isThinking && !widget.isRecording ? 0.6 : 0.25; duration: 1000; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0;  duration: 1000; easing.type: Easing.InOutSine }
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
                
                // Ocultar texto cuando el SiriOrb está activo para que no interfieran
                opacity: (widget.isRecording || widget.isTranscribing || widget.isThinking || widget.isSpeaking) ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 300 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󱜚"
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                    color: Theme.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: !widget.backendReady ? "Iniciando Minerva…" : (widget.hasPendingTasks ? "Minerva" : "Minerva")
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    font.weight:    Font.DemiBold
                    color: widget.hasPendingTasks ? Theme.warning : Theme.textPrimary
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 190)
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍬"
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    color: Theme.accent
                    visible: widget.backendReady
                    opacity: 0.5
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

    // ── Timer legacy (ya no se usa) ──────────────────────────────────────
    Timer {
        id: hideOrbTimer
        interval: 1500
        onTriggered: { /* no-op: lógica migrada a _updateMinervaState */ }
    }
}

