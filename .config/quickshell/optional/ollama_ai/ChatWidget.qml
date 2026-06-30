// optional/ollama_ai/ChatWidget.qml — Interfaz de chat completa del plugin Ollama AI
// Recibe mensajes del backend vía señal aiWidget.backendMessage y renderiza
// burbujas de chat, tarjetas de comandos y diálogo de confirmación.
import QtQuick
import "../../style"

Item {
    id: root

    // Referencia al Main.qml del plugin (inyectada desde expandedPanel)
    property var aiWidget: null

    // ── Estado de la conversación y del diálogo ───────────────────────────
    // Ahora todo el estado reside en aiWidget (Main.qml) para persistencia.
    // Solo referenciamos sus propiedades.

    // ── Escuchar mensajes del backend ─────────────────────────────────────
    Connections {
        target: root.aiWidget
        function onBackendMessage(msg) { root.handleMsg(msg) }
    }

    // ── Manejadores de mensajes ───────────────────────────────────────────
    function handleMsg(msg) {
        switch (msg.type) {
            case "token":
                onToken(msg.content || "")
                break
            case "done":
                onDone(msg.full_response || "")
                break
            case "tool_start":
                addSystemMsg(toolLabel(msg.tool || ""))
                break
            case "tool_result":
                break   // interno, no mostrar
            case "run_command":
                addCmdCard(msg.command || "", false, false)
                break
            case "confirm_required":
                addCmdCard(msg.command || "", true, false)
                aiWidget.pendingCmd    = msg.command || ""
                aiWidget.pendingIsSudo = false
                aiWidget.pendingReason = msg.reason  || "Comando potencialmente destructivo"
                aiWidget.showConfirm   = true
                break
            case "sudo_required":
                addCmdCard(msg.command || "", false, true)
                aiWidget.pendingCmd    = msg.command || ""
                aiWidget.pendingIsSudo = true
                aiWidget.pendingReason = "Este comando requiere permisos de administrador (pkexec)"
                aiWidget.showConfirm   = true
                break
            case "command_result":
                // Marcar la tarjeta de comando como completada para detener spinner
                for (var ci = aiWidget.msgModel.count - 1; ci >= 0; ci--) {
                    var citem = aiWidget.msgModel.get(ci)
                    if (citem.role === "command" && citem.cmdStatus === "running") {
                        aiWidget.msgModel.setProperty(ci, "cmdStatus", "done")
                        break
                    }
                }
                addResultCard(msg.command || "", msg.output || "", msg.success !== false)
                break
            case "error":
                if (aiWidget.streamingIdx >= 0) {
                    aiWidget.streamingIdx = -1
                    aiWidget.streamingRaw = ""
                }
                addSystemMsg("⚠ " + (msg.message || "Error desconocido"))
                break
        }
    }

    function toolLabel(t) {
        if (t === "list_dir")    return "󰏗  Listando directorio…"
        if (t === "read_file")   return "󰈙  Leyendo archivo…"
        if (t === "run_command") return "󰆍  Preparando comando…"
        return "󰏗  Usando herramienta…"
    }

    // ── Helpers de modelo ─────────────────────────────────────────────────
    function onToken(tok) {
        if (aiWidget.streamingIdx === -1) {
            aiWidget.msgModel.append({
                role: "ai", content: "", command: "", cmdStatus: "",
                needsConfirm: false, needsSudo: false, isSystem: false
            })
            aiWidget.streamingIdx = aiWidget.msgModel.count - 1
            aiWidget.streamingRaw = ""
        }
        aiWidget.streamingRaw += tok
        aiWidget.msgModel.setProperty(aiWidget.streamingIdx, "content", aiWidget.streamingRaw)
        scrollToBottom()
    }

    function onDone(fullRaw) {
        if (aiWidget.streamingIdx >= 0) {
            // Guardar el par completo en el historial
            aiWidget.conversationHistory.push(
                { role: "user",      content: aiWidget.currentUserMsg },
                { role: "assistant", content: fullRaw }
            )
        }
        aiWidget.streamingIdx = -1
        aiWidget.streamingRaw = ""
        scrollToBottom()
    }

    function addSystemMsg(text) {
        aiWidget.msgModel.append({
            role: "system", content: text, command: "", cmdStatus: "",
            needsConfirm: false, needsSudo: false, isSystem: true
        })
        scrollToBottom()
    }

    function addCmdCard(cmd, needsConfirm, needsSudo) {
        aiWidget.msgModel.append({
            role: "command", content: cmd, command: cmd, cmdStatus: "pending",
            needsConfirm: needsConfirm, needsSudo: needsSudo, isSystem: false
        })
        scrollToBottom()
    }

    function addResultCard(cmd, output, success) {
        aiWidget.msgModel.append({
            role: "result", content: output, command: cmd,
            cmdStatus: success ? "success" : "error",
            needsConfirm: false, needsSudo: false, isSystem: false
        })
        scrollToBottom()
    }

    function sendMessage() {
        var text = inputField.text.trim()
        if (!text || !root.aiWidget || root.aiWidget.isThinking) return

        inputField.text = ""
        aiWidget.currentUserMsg = text

        // Añadir burbuja de usuario
        aiWidget.msgModel.append({
            role: "user", content: text, command: "", cmdStatus: "",
            needsConfirm: false, needsSudo: false, isSystem: false
        })
        scrollToBottom()

        // Enviar al backend (historial sin el mensaje actual; backend lo añade)
        root.aiWidget.sendChat(text, aiWidget.conversationHistory.slice())
    }

    function clearChat() {
        aiWidget.msgModel.clear()
        aiWidget.conversationHistory = []
        aiWidget.currentUserMsg  = ""
        aiWidget.streamingIdx    = -1
        aiWidget.streamingRaw    = ""
        aiWidget.pendingCmd      = ""
        aiWidget.showConfirm     = false
        if (root.aiWidget) root.aiWidget.cancelRun()
    }

    function scrollToBottom() {
        Qt.callLater(function() {
            var maxY = Math.max(0, chatFlickable.contentHeight - chatFlickable.height)
            chatFlickable.contentY = maxY
        })
    }

    // ── UI ────────────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────
        Rectangle {
            id: chatHeader
            width:  parent.width
            height: 46
            color:  Qt.rgba(1, 1, 1, 0.04)

            // Izquierda: icono + nombre + dot de estado
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    text: "󱜚"
                    font.family: Theme.fontMono
                    font.pixelSize: 20
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: "Minerva"
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: Theme.textPrimary
                    }
                    Text {
                        text: root.aiWidget ? root.aiWidget.modelName : "…"
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        color: Theme.textMuted
                    }
                }

                Rectangle {
                    width: 7; height: 7; radius: 3.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.aiWidget && root.aiWidget.isThinking  ? Theme.warning
                         : root.aiWidget && root.aiWidget.backendReady ? Theme.success
                         : Theme.danger
                    Behavior on color { ColorAnimation { duration: 300 } }
                    SequentialAnimation on opacity {
                        running: root.aiWidget && root.aiWidget.isThinking
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.15; duration: 500 }
                        NumberAnimation { to: 1.0;  duration: 500 }
                        onStopped: opacity = 1.0
                    }
                }
            }

            // Derecha: botón reiniciar conversación
            Item {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30

                Rectangle {
                    anchors.fill: parent; radius: 8
                    color: clearHover.containsMouse ? Qt.rgba(1,1,1,0.08) : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    font.family: Theme.fontMono
                    font.pixelSize: 15
                    color: clearHover.containsMouse ? Theme.warning : Theme.textMuted
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                MouseArea {
                    id: clearHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearChat()
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: Qt.rgba(1, 1, 1, 0.07)
            }
        }

        // ── Área de mensajes ──────────────────────────────────────────────
        Item {
            width:  parent.width
            height: parent.height - chatHeader.height - inputBar.height

            Flickable {
                id: chatFlickable
                anchors.fill: parent
                contentWidth:  width
                contentHeight: msgsCol.implicitHeight + 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

            // Columna de mensajes
            Column {
                id: msgsCol
                width: chatFlickable.width
                topPadding:    10
                bottomPadding: 10
                leftPadding:   10
                rightPadding:  10
                spacing: 8

                Repeater {
                    model: root.aiWidget ? root.aiWidget.msgModel : null

                    delegate: Item {
                        id: msgDelegate
                        width: msgsCol.width - 20

                        // Altura determinada por el hijo visible
                        height: {
                            if (model.role === "user")                        return userBubble.implicitHeight
                            if (model.role === "ai")                          return aiBubble.implicitHeight
                            if (model.role === "command" || model.role === "result") return cmdCard.implicitHeight
                            if (model.isSystem)                               return sysMsg.implicitHeight + 4
                            return 0
                        }

                        // ── Burbuja usuario ───────────────────────────────
                        Rectangle {
                            id: userBubble
                            visible: model.role === "user"
                            implicitHeight: visible ? userTxt.implicitHeight + 18 : 0
                            width: Math.min(userTxt.implicitWidth + 30, msgDelegate.width * 0.82)
                            anchors.right: parent.right
                            radius: 16
                            color: Theme.accent

                            Text {
                                id: userTxt
                                anchors.centerIn: parent
                                width: parent.width - 30
                                text: model.content
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                color: "#0d0d0d"
                                wrapMode: Text.Wrap
                            }
                        }

                        // ── Burbuja IA ────────────────────────────────────
                        Rectangle {
                            id: aiBubble
                            visible: model.role === "ai"
                            implicitHeight: visible ? aiTxt.implicitHeight + 18 : 0
                            width: Math.min(aiTxt.implicitWidth + 30, msgDelegate.width * 0.92)
                            anchors.left: parent.left
                            radius: 16
                            color: Qt.rgba(1, 1, 1, 0.07)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.09)

                            Text {
                                id: aiTxt
                                anchors.centerIn: parent
                                width: parent.width - 30
                                // Cursor parpadeante al final mientras streamea
                                text: model.content
                                    + (root.aiWidget && root.aiWidget.streamingIdx === index && root.aiWidget.isThinking ? "▋" : "")
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                color: Theme.textPrimary
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                            }
                        }

                        // ── Tarjeta de comando / resultado ────────────────
                        Rectangle {
                            id: cmdCard
                            visible: model.role === "command" || model.role === "result"
                            implicitHeight: visible ? cardCol.implicitHeight + 20 : 0
                            width: msgDelegate.width
                            anchors.left: parent.left
                            radius: 14

                            // Color de fondo según tipo
                            color: model.role === "result"
                                ? (model.cmdStatus === "success"
                                   ? Qt.rgba(0.08, 0.28, 0.08, 0.55)
                                   : Qt.rgba(0.32, 0.07, 0.07, 0.55))
                                : Qt.rgba(1, 1, 1, 0.04)

                            border.width: 1
                            border.color: model.role === "result"
                                ? (model.cmdStatus === "success"
                                   ? Qt.rgba(0.3, 0.7, 0.3, 0.3)
                                   : Qt.rgba(0.8, 0.3, 0.3, 0.3))
                                : (model.needsConfirm || model.needsSudo)
                                  ? Qt.rgba(0.95, 0.65, 0.22, 0.45)
                                  : Qt.rgba(1, 1, 1, 0.09)

                            Column {
                                id: cardCol
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: parent.top; margins: 12
                                }
                                spacing: 8

                                // Cabecera de la tarjeta
                                Row {
                                    spacing: 6
                                    Text {
                                        text: model.role === "result"
                                            ? (model.cmdStatus === "success" ? "󰄬" : "󰅖")
                                            : model.needsSudo ? "󰌞"
                                            : model.needsConfirm ? "󰀦"
                                            : "󰆍"
                                        font.family: Theme.fontMono
                                        font.pixelSize: 13
                                        color: model.role === "result"
                                            ? (model.cmdStatus === "success" ? Theme.success : Theme.danger)
                                            : (model.needsSudo || model.needsConfirm)
                                              ? Theme.warning : Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: model.role === "result" ? "Resultado"
                                            : model.needsSudo ? "Requiere sudo (pkexec)"
                                            : model.needsConfirm ? "Confirmar antes de ejecutar"
                                            : "Ejecutar comando"
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Theme.textMuted
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // Línea del comando
                                Rectangle {
                                    width: cardCol.width
                                    height: cmdLineTxt.implicitHeight + 12
                                    radius: 8
                                    color: Qt.rgba(0, 0, 0, 0.35)

                                    Text {
                                        id: cmdLineTxt
                                        anchors {
                                            left: parent.left; right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            margins: 10
                                        }
                                        text: "$ " + (model.role === "result" ? model.command : model.content)
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                        color: (model.needsSudo || model.needsConfirm) ? Theme.warning : Theme.accent
                                        wrapMode: Text.Wrap
                                    }
                                }

                                // Output del resultado
                                Text {
                                    visible: model.role === "result" && model.content.length > 0
                                    width: cardCol.width
                                    text: model.content
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    color: model.cmdStatus === "success" ? Theme.textPrimary : Theme.danger
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 14
                                    elide: Text.ElideRight
                                }

                                // Botones de acción (pendiente)
                                Row {
                                    visible: model.role === "command" && model.cmdStatus === "pending"
                                    spacing: 8

                                    // Ejecutar
                                    Rectangle {
                                        height: 30
                                        width:  execLbl.implicitWidth + 24
                                        radius: 8
                                        color:  execMa.containsMouse
                                            ? Qt.rgba(0.15, 0.5, 0.15, 0.9)
                                            : Qt.rgba(0.08, 0.30, 0.08, 0.8)
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.success.r, Theme.success.g, Theme.success.b, 0.75)
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: "󰄬"
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                                color: Theme.success
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                id: execLbl
                                                text: model.needsSudo ? "Ejecutar (sudo)" : "Ejecutar"
                                                font.family: Theme.fontSans
                                                font.pixelSize: 12
                                                color: Theme.success
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: execMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var cmd       = model.content
                                                var isSudo    = model.needsSudo
                                                var isDestroy = model.needsConfirm

                                                if (isSudo) {
                                                    root.aiWidget.msgModel.setProperty(index, "cmdStatus", "running")
                                                    root.aiWidget.sudoRun(cmd)
                                                } else if (isDestroy) {
                                                    // Mostrar diálogo de confirmación destructiva
                                                    root.aiWidget.pendingCmd    = cmd
                                                    root.aiWidget.pendingIsSudo = false
                                                    root.aiWidget.pendingReason = "Este comando puede eliminar datos de forma irreversible"
                                                    root.aiWidget.showConfirm   = true
                                                } else {
                                                    root.aiWidget.msgModel.setProperty(index, "cmdStatus", "running")
                                                    root.aiWidget.confirmRun(cmd)
                                                }
                                            }
                                        }
                                    }

                                    // Cancelar
                                    Rectangle {
                                        height: 30
                                        width:  cancelLbl.implicitWidth + 24
                                        radius: 8
                                        color:  cancelMa.containsMouse
                                            ? Qt.rgba(0.4, 0.1, 0.1, 0.6)
                                            : Qt.rgba(0.22, 0.05, 0.05, 0.5)
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.5)
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            id: cancelLbl
                                            anchors.centerIn: parent
                                            text: "Cancelar"
                                            font.family: Theme.fontSans
                                            font.pixelSize: 12
                                            color: Theme.danger
                                        }
                                        MouseArea {
                                            id: cancelMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.aiWidget.msgModel.setProperty(index, "cmdStatus", "cancelled")
                                        }
                                    }
                                }

                                // Estado: ejecutando
                                Row {
                                    visible: model.role === "command" && model.cmdStatus === "running"
                                    spacing: 6
                                    Text {
                                        id: runningIcon
                                        text: "󰔟"
                                        font.family: Theme.fontMono
                                        font.pixelSize: 13
                                        color: Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                        SequentialAnimation on rotation {
                                            running: parent.visible
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 360; duration: 900; easing.type: Easing.Linear }
                                            onStopped: runningIcon.rotation = 0
                                        }
                                    }
                                    Text {
                                        text: "Ejecutando…"
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        color: Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // Estado: cancelado
                                Row {
                                    visible: model.role === "command" && model.cmdStatus === "cancelled"
                                    spacing: 6
                                    Text {
                                        text: "󰜺"
                                        font.family: Theme.fontMono
                                        font.pixelSize: 12
                                        color: Theme.textMuted
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "Cancelado"
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        color: Theme.textMuted
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }

                        // ── Mensaje de sistema ────────────────────────────
                        Text {
                            id: sysMsg
                            visible: model.isSystem
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: model.content
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            color: Theme.textMuted
                            opacity: 0.6
                        }
                    }
                }
            }
            } // Flickable

            // Estado vacío — overlay centrado sobre el Flickable
            Column {
                anchors.centerIn: parent
                visible: root.aiWidget && root.aiWidget.msgModel.count === 0
                spacing: 12
                opacity: 0.45

                Text {
                    text: "󱜚"
                    font.family: Theme.fontMono
                    font.pixelSize: 46
                    color: Theme.accent
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: root.aiWidget && root.aiWidget.backendReady
                        ? "¿En qué puedo ayudarte?"
                        : "Iniciando Minerva…"
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    color: Theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Tengo acceso a tu directorio home"
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    color: Theme.textMuted
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }

        // ── Barra de input ────────────────────────────────────────────────
        Rectangle {
            id: inputBar
            width:  parent.width
            height: 56
            color:  Qt.rgba(1, 1, 1, 0.03)

            Rectangle {
                anchors.top: parent.top
                width: parent.width; height: 1
                color: Qt.rgba(1, 1, 1, 0.07)
            }

            Row {
                anchors { fill: parent; margins: 8 }
                spacing: 8

                // Campo de texto
                Rectangle {
                    height: parent.height
                    width:  parent.width - 50
                    radius: 12
                    color:  Qt.rgba(1, 1, 1, 0.07)
                    border.width: inputField.activeFocus ? 1 : 0
                    border.color: Theme.accent
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextInput {
                        id: inputField
                        anchors { fill: parent; margins: 10 }
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        color: Theme.textPrimary
                        clip: true
                        readOnly: root.aiWidget && root.aiWidget.isThinking

                        // Placeholder manual
                        Text {
                            visible: !inputField.text && !inputField.activeFocus
                            text: root.aiWidget && root.aiWidget.isThinking
                                ? "Esperando respuesta…"
                                : "Escribe un mensaje…  Enter para enviar"
                            font: inputField.font
                            color: Theme.textMuted
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        }

                        Keys.onReturnPressed: function(e) {
                            if (!(e.modifiers & Qt.ShiftModifier))
                                root.sendMessage()
                        }
                    }
                }

                // Botón enviar / spinner
                Rectangle {
                    width:  42
                    height: parent.height
                    radius: 12
                    color: sendMa.containsMouse && !(root.aiWidget && root.aiWidget.isThinking)
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                        : Qt.rgba(1, 1, 1, 0.07)
                    opacity: (root.aiWidget && root.aiWidget.isThinking) ? 0.4 : 1.0
                    Behavior on color   { ColorAnimation  { duration: 150 } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Text {
                        id: sendIcon
                        anchors.centerIn: parent
                        text: (root.aiWidget && root.aiWidget.isThinking) ? "󰔟" : "󰒊"
                        font.family: Theme.fontMono
                        font.pixelSize: 20
                        color: Theme.accent
                        SequentialAnimation on rotation {
                            running: root.aiWidget && root.aiWidget.isThinking
                            loops: Animation.Infinite
                            NumberAnimation { to: 360; duration: 900; easing.type: Easing.Linear }
                            onStopped: sendIcon.rotation = 0
                        }
                    }

                    MouseArea {
                        id: sendMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !(root.aiWidget && root.aiWidget.isThinking)
                        onClicked: root.sendMessage()
                    }
                }
            }
        }
    }

    // ── Overlay de confirmación ───────────────────────────────────────────
    // Aparece para comandos destructivos o sudo, solicita confirmación explícita.
    Rectangle {
        id: confirmOverlay
        anchors.fill: parent
        visible: root.aiWidget ? root.aiWidget.showConfirm : false
        color: Qt.rgba(0, 0, 0, 0.72)

        // Entrada con animación
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // Caja del diálogo
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width - 36
            height: dlgCol.implicitHeight + 44
            radius: 18
            color:  "#141422"
            border.width: 1
            border.color: Qt.rgba(0.95, 0.65, 0.2, 0.55)

            // Sombra sutil
            layer.enabled: true

            Column {
                id: dlgCol
                anchors.centerIn: parent
                width: parent.width - 44
                spacing: 16

                // Icono + título
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Text {
                        text: root.aiWidget && root.aiWidget.pendingIsSudo ? "󰌞" : "󰀦"
                        font.family: Theme.fontMono
                        font.pixelSize: 28
                        color: Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            text: root.aiWidget && root.aiWidget.pendingIsSudo ? "Permisos elevados" : "¿Confirmar acción?"
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Theme.warning
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: root.aiWidget ? root.aiWidget.pendingReason : ""
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    color: Theme.textMuted
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }

                // Comando a confirmar
                Rectangle {
                    width: parent.width
                    height: dlgCmdTxt.implicitHeight + 16
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.45)
                    border.width: 1
                    border.color: Qt.rgba(0.95, 0.65, 0.2, 0.25)

                    Text {
                        id: dlgCmdTxt
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 12
                        }
                        text: "$ " + (root.aiWidget ? root.aiWidget.pendingCmd : "")
                        font.family: Theme.fontMono
                        font.pixelSize: 12
                        color: Theme.warning
                        wrapMode: Text.Wrap
                    }
                }

                // Botones
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    // Cancelar
                    Rectangle {
                        width: 100; height: 36; radius: 10
                        color: dlgCancelMa.containsMouse ? Qt.rgba(0.3,0.3,0.3,0.4) : Qt.rgba(0.15,0.15,0.15,0.4)
                        border.width: 1; border.color: Qt.rgba(1,1,1,0.2)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: "Cancelar"
                            font.family: Theme.fontSans; font.pixelSize: 13
                            color: Theme.textPrimary
                        }
                        MouseArea {
                            id: dlgCancelMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.aiWidget) root.aiWidget.showConfirm = false
                        }
                    }

                    // Ejecutar de todos modos
                    Rectangle {
                        width: root.aiWidget && root.aiWidget.pendingIsSudo ? 150 : 170
                        height: 36; radius: 10
                        color: dlgExecMa.containsMouse ? Qt.rgba(0.75,0.45,0.08,0.55) : Qt.rgba(0.5,0.28,0.04,0.4)
                        border.width: 1; border.color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.75)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: root.aiWidget && root.aiWidget.pendingIsSudo ? "Ejecutar (pkexec)" : "Ejecutar de todos modos"
                            font.family: Theme.fontSans; font.pixelSize: 12
                            color: Theme.warning
                        }
                        MouseArea {
                            id: dlgExecMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.aiWidget) return
                                root.aiWidget.showConfirm = false
                                // Marcar la tarjeta como "running"
                                for (var i = root.aiWidget.msgModel.count - 1; i >= 0; i--) {
                                    if (root.aiWidget.msgModel.get(i).role === "command" &&
                                        root.aiWidget.msgModel.get(i).content === root.aiWidget.pendingCmd) {
                                        root.aiWidget.msgModel.setProperty(i, "cmdStatus", "running")
                                        break
                                    }
                                }
                                if (root.aiWidget.pendingIsSudo) {
                                    root.aiWidget.sudoRun(root.aiWidget.pendingCmd)
                                } else {
                                    root.aiWidget.confirmRun(root.aiWidget.pendingCmd)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
