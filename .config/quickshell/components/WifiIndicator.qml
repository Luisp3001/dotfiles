// components/WifiIndicator.qml — Estado de red via nmcli (WiFi + Ethernet)
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../style"

Item {
    id: root

    implicitWidth: iconLabel.implicitWidth
    implicitHeight: iconLabel.implicitHeight

    // ── Estado ────────────────────────────────────────────────────────────────
    property string iconText: "󰤭"       // ícono actual (sin wifi por defecto)
    property color  iconColor: Theme.textMuted
    property string tipText:  "Sin conexión"

    // ── Proceso: consulta nmcli para obtener estado de red ────────────────────
    Process {
        id: wifiProc
        command: ["bash", "-c", `
            # 1. Verificar conexión por cable (Ethernet)
            WIRED=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null \
                | awk -F: '$2=="802-3-ethernet" && $3=="activated"{print $1; exit}')

            if [ -n "$WIRED" ]; then
                # Obtener nombre de la conexión ethernet activa
                WIRED_NAME=$(nmcli -g NAME,TYPE connection show --active 2>/dev/null \
                    | awk -F: '$2=="802-3-ethernet"{print $1; exit}')
                echo "NET:wired"
                echo "WIRED_NAME:$WIRED_NAME"
                exit 0
            fi

            # Verificar si hay un cable conectado pero sin IP (activating)
            WIRED_ING=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null \
                | awk -F: '$2=="802-3-ethernet" && $3=="activating"{print $1; exit}')
            if [ -n "$WIRED_ING" ]; then
                echo "NET:wired_activating"
                exit 0
            fi

            # Verificar si hay un dispositivo ethernet conectado físicamente
            ETH_DEV=$(nmcli -g DEVICE,TYPE,STATE device status 2>/dev/null \
                | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}')
            if [ -n "$ETH_DEV" ]; then
                echo "NET:wired"
                echo "WIRED_NAME:$ETH_DEV"
                exit 0
            fi

            # 2. Si no hay cable, verificar WiFi
            echo "NET:wifi"

            # Estado del radio WiFi
            WIFI_STATE=$(nmcli -g WIFI radio 2>/dev/null || echo "unknown")
            echo "WIFI:$WIFI_STATE"

            if [ "$WIFI_STATE" != "enabled" ]; then
                exit 0
            fi

            # Buscar conexión WiFi activa
            ACTIVE=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null \
                | awk -F: '$2=="802-11-wireless" && $3=="activated"{print $1; exit}')

            if [ -z "$ACTIVE" ]; then
                # Verificar si está conectando
                ACTIVATING=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null \
                    | awk -F: '$2=="802-11-wireless" && $3=="activating"{print $1; exit}')
                if [ -n "$ACTIVATING" ]; then
                    echo "STATE:activating"
                    exit 0
                fi
                echo "STATE:disconnected"
                exit 0
            fi

            echo "STATE:activated"

            # Señal del AP actual
            SIGNAL=$(nmcli -g IN-USE,SIGNAL dev wifi list 2>/dev/null \
                | awk -F: '$1=="*"{print $2; exit}')
            echo "SIGNAL:$SIGNAL"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text || "").split(/\r?\n/)
                let net = "", wifi = "", state = "", signal = "", wiredName = ""

                for (let line of lines) {
                    const parts = line.trim().split(":")
                    if (parts.length < 2) continue
                    const key = parts[0]
                    const val = parts.slice(1).join(":")

                    if (key === "NET")        net = val
                    else if (key === "WIFI")       wifi = val
                    else if (key === "STATE")      state = val
                    else if (key === "SIGNAL")     signal = val
                    else if (key === "WIRED_NAME") wiredName = val
                }

                // ── Conexión por cable ──
                if (net === "wired") {
                    root.iconText  = "󰈀"   // ethernet icon
                    root.iconColor = Theme.success
                    root.tipText   = "Ethernet" + (wiredName ? " (" + wiredName + ")" : "")
                    return
                }

                if (net === "wired_activating") {
                    root.iconText  = "󰈀"
                    root.iconColor = Theme.warning
                    root.tipText   = "Ethernet conectando…"
                    return
                }

                // ── WiFi ──
                // WiFi apagado
                if (wifi !== "enabled") {
                    root.iconText  = "󰤮"
                    root.iconColor = Theme.danger
                    root.tipText   = "WiFi apagado"
                    return
                }

                // Conectado
                if (state === "activated") {
                    const sig = parseInt(signal, 10)
                    const s = isFinite(sig) ? sig : 0

                    if (s > 80)      root.iconText = "󰤨"
                    else if (s > 60) root.iconText = "󰤥"
                    else if (s > 40) root.iconText = "󰤢"
                    else if (s > 20) root.iconText = "󰤟"
                    else             root.iconText = "󰤯"

                    root.iconColor = Theme.success
                    root.tipText   = "Conectado (" + s + "%)"
                }
                // Conectando
                else if (state === "activating") {
                    root.iconText  = "󰤦"
                    root.iconColor = Theme.warning
                    root.tipText   = "Conectando…"
                }
                // Desconectado
                else {
                    root.iconText  = "󰤭"
                    root.iconColor = Theme.danger
                    root.tipText   = "Sin conexión"
                }
            }
        }
    }

    function refreshWifi() {
        wifiProc.running = true
    }

    // Refrescar cada 5 segundos
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: root.refreshWifi()
    }

    Component.onCompleted: refreshWifi()

    // ── UI ────────────────────────────────────────────────────────────────────
    Text {
        id: iconLabel
        text: root.iconText
        color: root.iconColor
        font.family: Theme.fontMono
        font.pixelSize: Theme.iconSize + 2
        anchors.centerIn: parent
    }

    MouseArea {
        id: wifiArea
        anchors.fill: parent
        hoverEnabled: true
    }

    ToolTip {
        visible: wifiArea.containsMouse
        text: root.tipText
        delay: 400
    }
}
