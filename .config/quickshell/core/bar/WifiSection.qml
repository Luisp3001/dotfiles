// modules/bar/WifiSection.qml — WiFi menu embebido para el centro de notificaciones
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../style"

Item {
    id: root

    property var shellRoot: null

    // ── Constants ────────────────────────────────────────────────────────
    readonly property int statusRefreshInterval: 5000
    readonly property int processTimeout: 20000
    readonly property int scanDebounceDelay: 500

    // ── Colors (from Theme) ─────────────────────────────────────────────
    readonly property color cFg:     Theme.textPrimary
    readonly property color cMuted:  Theme.textMuted
    readonly property color cGreen:  Theme.success
    readonly property color cRed:    Theme.danger
    readonly property color cBlue:   Theme.accent
    readonly property color cBorder: Theme.accentDim
    readonly property color cBgAlt:  Qt.rgba(1, 1, 1, 0.06)
    readonly property color cCard:   Theme.bgPill

    readonly property string fontText: Theme.fontSans
    readonly property string fontIcon: Theme.fontMono

    // ── State ───────────────────────────────────────────────────────────

    property bool isBusy: false
    property bool scanRunning: false
    property bool wifiEnabled: true
    property string activeConnectionUuid: ""
    property string currentSsid: "Checking…"
    property int currentSignalVal: 0
    property string currentIp: ""
    property string statusLine: ""
    property color statusColor: cMuted
    property string targetSsid: ""
    property bool targetIsEnterprise: false
    property string enteredUser: ""
    property string enteredPass: ""
    property string pendingSavedUuid: ""
    property string pendingSavedSsid: ""

    onVisibleChanged: {
        if (visible) {
            refreshStatus()
            // Auto-scan on visible
            networkModel.clear(); ssidMap = ({}); ssidBestSignal = ({})
            refreshSaved(); scanDebounce.restart()
        } else {
            viewStack.currentIndex = 0
            targetSsid = ""
            enteredPass = ""
        }
    }

    Timer { id: statusTimer; interval: 3200; repeat: false; onTriggered: statusLine = "" }
    Timer {
        id: processWatchdog; interval: processTimeout; repeat: false
        onTriggered: { if (isBusy || scanRunning) setStatus("Operation timed out", true) }
    }
    Timer { id: scanDebounce; interval: scanDebounceDelay; repeat: false; onTriggered: performScan() }

    function setStatus(msg, bad) { statusLine = msg; statusColor = bad ? cRed : cMuted; statusTimer.restart() }
    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function getSignalIcon(strength) {
        if (strength > 80) return "󰤨"
        if (strength > 60) return "󰤥"
        if (strength > 40) return "󰤢"
        if (strength > 20) return "󰤟"
        return "󰤯"
    }
    function securityIsEnterprise(sec) { var s = String(sec || ""); return s.includes("802.1X") || s.includes("Enterprise") }
    function securityLabel(sec, isEnt) {
        if (isEnt) return "Enterprise"
        var s = String(sec || "").trim()
        if (s === "" || s === "--") return "Open"
        return "Secured"
    }

    // ── Status Process ──────────────────────────────────────────────────
    Process {
        id: procStatus
        command: ["bash", "-c", `
            WIFI_STATE=$(nmcli -g WIFI radio 2>/dev/null || echo "unknown")
            echo "WIFI:$WIFI_STATE"
            if [ "$WIFI_STATE" != "enabled" ]; then exit 0; fi
            ACTIVE=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless" && $3=="activated"{print $1; exit}')
            if [ -z "$ACTIVE" ]; then
                ACTIVATING=$(nmcli -g UUID,TYPE,STATE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless" && $3=="activating"{print $1; exit}')
                if [ -n "$ACTIVATING" ]; then echo "UUID:$ACTIVATING"; echo "STATE:activating"; exit 0; fi
                echo "STATE:disconnected"; exit 0
            fi
            echo "UUID:$ACTIVE"; echo "STATE:activated"
            SSID=$(nmcli -g 802-11-wireless.ssid connection show uuid "$ACTIVE" 2>/dev/null | head -n1)
            echo "SSID:$SSID"
            SIGNAL=$(nmcli -g IN-USE,SIGNAL dev wifi list 2>/dev/null | awk -F: '$1=="*"{print $2; exit}')
            echo "SIGNAL:$SIGNAL"
            IP=$(ip -o route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
            echo "IP:$IP"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text || "").split(/\r?\n/)
                let wifi = "", uuid = "", state = "", ssid = "", signal = "", ip = ""
                for (let line of lines) {
                    const parts = line.trim().split(":")
                    if (parts.length < 2) continue
                    const key = parts[0], val = parts.slice(1).join(":")
                    if (key === "WIFI") wifi = val
                    else if (key === "UUID") uuid = val
                    else if (key === "STATE") state = val
                    else if (key === "SSID") ssid = val
                    else if (key === "SIGNAL") signal = val
                    else if (key === "IP") ip = val
                }
                wifiEnabled = (wifi === "enabled")
                if (!wifiEnabled) { currentSsid = "WiFi Off"; currentIp = ""; currentSignalVal = 0; activeConnectionUuid = ""; return }
                activeConnectionUuid = uuid
                if (state === "activated") { currentSsid = ssid || "Connected"; const sig = parseInt(signal, 10); currentSignalVal = isFinite(sig) ? sig : 0; currentIp = ip }
                else if (state === "activating") { currentSsid = "Connecting…"; currentIp = ""; currentSignalVal = 0 }
                else { currentSsid = "Disconnected"; currentIp = ""; currentSignalVal = 0 }
            }
        }
    }
    function refreshStatus() { procStatus.running = true }

    // ── Saved Networks ──────────────────────────────────────────────────
    ListModel { id: savedModel }
    property var savedBySsid: ({})
    property var savedByUuid: ({})

    function markSavedFlags() {
        const updates = []
        for (let i = 0; i < networkModel.count; i++) {
            const item = networkModel.get(i)
            const wasSaved = item.isSaved
            const nowSaved = (savedBySsid[item.ssid] !== undefined)
            if (wasSaved !== nowSaved) updates.push({index: i, value: nowSaved})
        }
        for (let u of updates) networkModel.setProperty(u.index, "isSaved", u.value)
    }

    Process {
        id: procSaved
        command: ["bash", "-c", `
            nmcli -t -f UUID,TYPE connection show 2>/dev/null \
            | awk -F: '$2=="802-11-wireless"{print $1}' \
            | while IFS= read -r uuid; do
                mapfile -t vals < <(nmcli -g 802-11-wireless.ssid,connection.id connection show uuid "$uuid" 2>/dev/null)
                ssid="\${vals[0]}"; name="\${vals[1]}"
                [ -z "$name" ] && name="$ssid"; [ -z "$ssid" ] && ssid="$name"; [ -z "$ssid" ] && continue
                printf '%s\\t%s\\t%s\\n' "$uuid" "$ssid" "$name"
            done
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                savedModel.clear(); savedBySsid = ({}); savedByUuid = ({})
                const lines = String(text || "").split(/\r?\n/)
                for (let line of lines) {
                    if (!line.trim()) continue
                    const parts = line.split("\t")
                    if (parts.length < 3) continue
                    const uuid = parts[0].trim(), ssid = parts[1].trim(), name = parts[2].trim()
                    if (!uuid || !ssid) continue
                    if (savedBySsid[ssid] === undefined) {
                        savedModel.append({ ssid, name, uuid })
                        savedBySsid[ssid] = { uuid, name }
                    }
                    savedByUuid[uuid] = { ssid, name }
                }
                markSavedFlags()
            }
        }
    }
    function refreshSaved() { procSaved.running = true }

    // ── Network Model ───────────────────────────────────────────────────
    ListModel { id: networkModel }
    property var ssidMap: ({})
    property var ssidBestSignal: ({})

    function upsertNetwork(ssid, bssid, sec, sig) {
        if (!ssid || ssid.length === 0) return
        if (!bssid || bssid.length === 0) return
        const ent = securityIsEnterprise(sec)
        const isSaved = (savedBySsid[ssid] !== undefined)
        if (ssidBestSignal[ssid] === undefined || sig > ssidBestSignal[ssid]) ssidBestSignal[ssid] = sig
        if (ssidMap[ssid] !== undefined) {
            const idx = ssidMap[ssid]
            if (idx < networkModel.count) {
                const current = networkModel.get(idx)
                if (sig > current.strength) {
                    networkModel.setProperty(idx, "bssid", bssid)
                    networkModel.setProperty(idx, "security", sec || "")
                    networkModel.setProperty(idx, "strength", sig)
                    networkModel.setProperty(idx, "isEnterprise", ent)
                    networkModel.setProperty(idx, "isSaved", isSaved)
                }
            }
            return
        }
        networkModel.append({ ssid, bssid, security: sec || "", strength: sig, isEnterprise: ent, isSaved })
        ssidMap[ssid] = networkModel.count - 1
    }

    function parseScanOutput(raw) {
        const lines = String(raw || "").split(/\r?\n/)
        for (let line of lines) {
            line = line.trim(); if (!line) continue
            const safeLine = line.replace(/\\:/g, "___COLON___")
            const parts = safeLine.split(":")
            if (parts.length < 4) continue
            const bssid = parts[0].replace(/___COLON___/g, ":")
            const ssid = parts[1].replace(/___COLON___/g, ":")
            const sec = parts[2].replace(/___COLON___/g, ":")
            let sig = parseInt(parts[3], 10)
            if (!isFinite(sig)) sig = 0
            if (!ssid || ssid.length === 0) continue
            upsertNetwork(ssid, bssid, sec, sig)
        }
    }

    // ── Scanner ─────────────────────────────────────────────────────────
    Process {
        id: scanner
        command: ["bash", "-c", "nmcli -g BSSID,SSID,SECURITY,SIGNAL dev wifi list --rescan yes 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                scanRunning = false; processWatchdog.stop()
                parseScanOutput(text || "")
                refreshSaved()
                if (networkModel.count === 0 && savedModel.count === 0) setStatus("No networks found", true)
                else setStatus("Networks updated", false)
            }
        }
        onExited: { if (exitCode !== 0 && scanRunning) { scanRunning = false; processWatchdog.stop(); setStatus("Scan failed", true) } }
    }
    function performScan() {
        if (!wifiEnabled) { setStatus("WiFi is off", true); return }
        scanRunning = true; processWatchdog.restart(); scanner.running = true
    }

    // ── Runner ──────────────────────────────────────────────────────────
    Process {
        id: runner
        stdout: StdioCollector {
            onStreamFinished: {
                isBusy = false; processWatchdog.stop()
                const out = String(text || ""); const ok = out.includes("__EXIT:0")
                if (ok) { setStatus("Connected", false); errorBox.visible = false; viewStack.currentIndex = 0; statusRefreshDelay.restart(); return }
                if (out.includes("Secrets were required") || out.includes("No suitable secrets")) {
                    errorBox.visible = false; setStatus("Password required", true)
                    targetSsid = pendingSavedSsid; viewStack.currentIndex = 1
                    Qt.callLater(() => { if (targetIsEnterprise) userField.forceActiveFocus(); else passField.forceActiveFocus() })
                    return
                }
                const lines = out.trim().split(/\r?\n/)
                const tail = lines.slice(Math.max(0, lines.length - 10)).join("\n")
                errorBox.text = tail.length ? tail : "Connection failed."
                errorBox.visible = true; setStatus("Connection failed", true)
                refreshStatus(); refreshSaved()
            }
        }
        onExited: { if (exitCode !== 0 && isBusy) { isBusy = false; processWatchdog.stop(); setStatus("Connection failed", true) } }
    }
    Timer { id: statusRefreshDelay; interval: 1500; repeat: false; onTriggered: { refreshStatus(); refreshSaved() } }

    function runWithExit(cmdString) {
        if (isBusy) return; isBusy = true; processWatchdog.restart()
        errorBox.visible = false; setStatus("Working…", false)
        runner.command = ["bash", "-c", cmdString + " 2>&1; rc=$?; echo __EXIT:$rc"]
        runner.running = true
    }
    function connectSaved(uuid, ssid) {
        pendingSavedUuid = uuid; pendingSavedSsid = ssid
        if (!uuid || uuid === "") { setStatus("Invalid connection", true); return }
        runWithExit("nmcli -w 15 connection up uuid " + shellQuote(uuid))
    }
    function setSavedPskAndConnect(uuid, password) {
        runWithExit("nmcli connection modify uuid " + shellQuote(uuid) +
            " 802-11-wireless-security.key-mgmt wpa-psk" +
            " 802-11-wireless-security.psk " + shellQuote(password) + " && " +
            "nmcli -w 15 connection up uuid " + shellQuote(uuid))
    }
    function connectNew(ssid, password, username, isEnterprise) {
        if (savedBySsid[ssid] !== undefined) { connectSaved(savedBySsid[ssid].uuid, ssid); return }
        let cmd = ""
        if (isEnterprise) {
            cmd = "nmcli -w 20 dev wifi connect " + shellQuote(ssid) +
                " password " + shellQuote(password) +
                " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity " + shellQuote(username)
        } else {
            cmd = "nmcli -w 20 dev wifi connect " + shellQuote(ssid)
            if (password && password.trim().length > 0) cmd += " password " + shellQuote(password)
        }
        pendingSavedUuid = ""; pendingSavedSsid = ssid; runWithExit(cmd)
    }
    function toggleWifi() { if (isBusy) return; runWithExit("nmcli radio wifi " + (wifiEnabled ? "off" : "on")) }
    function disconnectNetwork() {
        if (isBusy) return
        if (!activeConnectionUuid || activeConnectionUuid === "") { setStatus("No active connection", true); return }
        runWithExit("nmcli connection down uuid " + shellQuote(activeConnectionUuid))
    }
    function rescanNow() { if (isBusy || !wifiEnabled) return; networkModel.clear(); ssidMap = ({}); ssidBestSignal = ({}); scanDebounce.restart() }
    function openAdvancedEditor() { Quickshell.execDetached(["nm-connection-editor"]) }

    // ── Periodic refresh ────────────────────────────────────────────────
    Timer {
        interval: statusRefreshInterval; repeat: true; running: root.visible; triggeredOnStart: false
        onTriggered: { if (!isBusy && !scanRunning) refreshStatus() }
    }
    Component.onCompleted: { refreshStatus(); Qt.callLater(() => refreshSaved()) }

    // ── UI ──────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "  Internet"
                color: cFg
                font.family: fontText
                font.pixelSize: 14
                font.weight: Font.Bold
                Layout.fillWidth: true
            }

            // Toggle switch
            Rectangle {
                width: 42; height: 22; radius: 11
                color: wifiEnabled ? Qt.rgba(cGreen.r, cGreen.g, cGreen.b, 0.95) : cBgAlt
                border.width: 1
                border.color: wifiEnabled ? Qt.rgba(cGreen.r, cGreen.g, cGreen.b, 0.55) : cBorder
                opacity: isBusy ? 0.6 : 1.0
                Rectangle {
                    width: 16; height: 16; radius: 8; color: cCard
                    anchors.verticalCenter: parent.verticalCenter
                    x: wifiEnabled ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !isBusy
                    onClicked: toggleWifi()
                }
            }
        }

        // ── Status Card (compact) ───────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 52; radius: 12
            color: cBgAlt; border.width: 0

            RowLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 10
                Text {
                    text: wifiEnabled ? getSignalIcon(currentSignalVal) : "󰤮"
                    font.pixelSize: 16; font.family: fontIcon
                    color: wifiEnabled ? cGreen : cMuted
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    Text {
                        text: currentSsid; font.family: fontText; font.pixelSize: 12; font.weight: Font.Bold
                        color: cFg; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                    Text {
                        text: (currentIp && currentIp.length > 0) ? currentIp : (wifiEnabled ? "No IP" : "Off")
                        font.family: fontText; font.pixelSize: 10; color: cMuted; elide: Text.ElideRight; Layout.fillWidth: true
                    }
                }
                Rectangle {
                    visible: wifiEnabled && activeConnectionUuid !== ""
                    width: 28; height: 28; radius: 10
                    color: discMouse.containsMouse ? Qt.rgba(cRed.r, cRed.g, cRed.b, 0.12) : "transparent"
                    Text { anchors.centerIn: parent; text: "󰅙"; font.family: fontIcon; color: cRed; font.pixelSize: 12 }
                    MouseArea {
                        id: discMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor; enabled: !isBusy
                        onClicked: disconnectNetwork()
                    }
                }
            }
        }

        Text {
            visible: statusLine.length > 0; text: statusLine; font.family: fontText; font.pixelSize: 10; color: statusColor
        }

        TextArea {
            id: errorBox; visible: false; readOnly: true; wrapMode: Text.Wrap
            Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight + 16, 80)
            font.family: fontText; font.pixelSize: 10; color: cRed
            background: Rectangle { radius: 10; color: Qt.rgba(cRed.r, cRed.g, cRed.b, 0.08); border.width: 1; border.color: Qt.rgba(cRed.r, cRed.g, cRed.b, 0.25) }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: cBorder; opacity: 0.5 }

        // ── Network Lists / Password ────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true

            StackLayout {
                id: viewStack; anchors.fill: parent; currentIndex: 0

                // 0 = Network Lists
                ColumnLayout {
                    spacing: 4

                    Item {
                        Layout.fillWidth: true; Layout.preferredHeight: 40
                        visible: !scanRunning && savedModel.count === 0 && networkModel.count === 0
                        Column {
                            anchors.centerIn: parent; spacing: 4
                            Text { text: "No networks found"; font.family: fontText; font.pixelSize: 12; font.weight: Font.Bold; color: cFg; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: "Scanning…"; font.family: fontText; font.pixelSize: 10; color: cMuted; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                    }

                    Text {
                        text: "Saved"; font.family: fontText; font.pixelSize: 11; font.weight: Font.Bold; color: cMuted
                        visible: savedModel.count > 0
                    }

                    ListView {
                        Layout.fillWidth: true; Layout.preferredHeight: Math.min(100, Math.max(0, savedModel.count * 34))
                        visible: savedModel.count > 0; clip: true; model: savedModel; spacing: 2
                        delegate: savedDelegate
                    }

                    Text {
                        text: "Available"; font.family: fontText; font.pixelSize: 11; font.weight: Font.Bold; color: cMuted
                        visible: networkModel.count > 0
                    }

                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        visible: networkModel.count > 0; clip: true; model: networkModel; spacing: 2
                        delegate: networkDelegate
                    }
                }

                // 1 = Password Entry
                ColumnLayout {
                    spacing: 10

                    Text {
                        text: targetIsEnterprise ? ("Log in to " + targetSsid) : ("Password for " + targetSsid)
                        color: cFg; font.family: fontText; font.pixelSize: 13; font.weight: Font.Bold
                        Layout.fillWidth: true; elide: Text.ElideRight
                    }

                    PillField {
                        id: userField; visible: targetIsEnterprise; Layout.fillWidth: true
                        placeholder: "Username"; text: enteredUser; enabled: !isBusy
                        onTextChanged: enteredUser = text; onAccepted: passField.forceActiveFocus()
                    }

                    PillField {
                        id: passField; Layout.fillWidth: true; placeholder: "Password"
                        echoMode: TextInput.Password; text: enteredPass; enabled: !isBusy
                        onTextChanged: enteredPass = text
                        onAccepted: {
                            if (pendingSavedUuid !== "") setSavedPskAndConnect(pendingSavedUuid, enteredPass)
                            else connectNew(targetSsid, enteredPass, enteredUser, targetIsEnterprise)
                        }
                    }

                    RowLayout {
                        spacing: 8; Layout.fillWidth: true
                        MenuButton {
                            Layout.fillWidth: true; height: 32; text: "Back"; icon: "󰁍"; kind: "outline"
                            disabled: isBusy; onClicked: viewStack.currentIndex = 0
                        }
                        MenuButton {
                            Layout.fillWidth: true; height: 32
                            text: isBusy ? "Connecting…" : "Connect"
                            btnColor: Theme.success; textColor: "#1e2326"; icon: "󱄙"; kind: "primary"
                            disabled: isBusy
                            onClicked: {
                                if (pendingSavedUuid !== "") setSavedPskAndConnect(pendingSavedUuid, enteredPass)
                                else connectNew(targetSsid, enteredPass, enteredUser, targetIsEnterprise)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Delegates ───────────────────────────────────────────────────────
    Component {
        id: savedDelegate
        Rectangle {
            required property string ssid
            required property string uuid
            required property string name
            width: ListView.view ? ListView.view.width : 0; height: 30; radius: 10
            color: sm.containsMouse ? Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.10) : "transparent"
            border.width: sm.containsMouse ? 1 : 0
            border.color: Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.25)
            opacity: isBusy ? 0.6 : 1.0
            RowLayout {
                anchors.fill: parent; anchors.margins: 8; spacing: 8
                Text { text: "󰤨"; font.family: fontIcon; font.pixelSize: 12; color: cGreen }
                Text {
                    text: parent.parent.name || parent.parent.ssid || ""
                    font.family: fontText; font.pixelSize: 12; font.weight: Font.Bold; color: cFg
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                Text { text: "Saved"; font.family: fontText; font.pixelSize: 9; color: cMuted }
            }
            MouseArea {
                id: sm; anchors.fill: parent; hoverEnabled: true
                cursorShape: isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor; enabled: !isBusy
                onClicked: connectSaved(parent.uuid, parent.ssid)
            }
        }
    }

    Component {
        id: networkDelegate
        Rectangle {
            required property string ssid
            required property string bssid
            required property string security
            required property int strength
            required property bool isEnterprise
            required property bool isSaved
            width: ListView.view ? ListView.view.width : 0; height: 38; radius: 10
            color: nm.containsMouse ? Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.10) : "transparent"
            border.width: nm.containsMouse ? 1 : 0
            border.color: Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.25)
            opacity: isBusy ? 0.6 : 1.0
            RowLayout {
                anchors.fill: parent; anchors.margins: 8; spacing: 8
                Text { text: getSignalIcon(parent.parent.strength); font.family: fontIcon; font.pixelSize: 12; color: cGreen }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    Text {
                        text: parent.parent.parent.ssid || ""; font.family: fontText; font.pixelSize: 12; font.weight: Font.Bold
                        color: cFg; Layout.fillWidth: true; elide: Text.ElideRight
                    }
                    Text {
                        text: parent.parent.parent.isSaved ? "Saved" : securityLabel(parent.parent.parent.security, parent.parent.parent.isEnterprise)
                        font.family: fontText; font.pixelSize: 9; color: cMuted
                    }
                }
                Text {
                    text: { const sec = parent.parent.security || ""; return (parent.parent.isSaved || (sec.trim() !== "" && sec !== "--")) ? "󰌾" : "󰦝" }
                    font.family: fontIcon; font.pixelSize: 10; color: cMuted
                }
            }
            MouseArea {
                id: nm; anchors.fill: parent; hoverEnabled: true
                cursorShape: isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor; enabled: !isBusy
                onClicked: {
                    const item = parent
                    if (item.isSaved) { let uuid = savedBySsid[item.ssid] ? savedBySsid[item.ssid].uuid : ""; if (uuid) connectSaved(uuid, item.ssid); return }
                    const sec = String(item.security || "").trim()
                    if (sec === "" || sec === "--") { pendingSavedUuid = ""; pendingSavedSsid = item.ssid; connectNew(item.ssid, "", "", item.isEnterprise); return }
                    targetSsid = item.ssid; targetIsEnterprise = item.isEnterprise; enteredUser = ""; enteredPass = ""
                    pendingSavedUuid = ""; pendingSavedSsid = item.ssid; viewStack.currentIndex = 1
                    Qt.callLater(() => { if (targetIsEnterprise) userField.forceActiveFocus(); else passField.forceActiveFocus() })
                }
            }
        }
    }

    // ── Inline Components ───────────────────────────────────────────────
    component MenuButton: Rectangle {
        id: btn
        property string text: ""
        property string icon: ""
        property string kind: "outline"
        property bool disabled: false
        property color btnColor: cGreen
        property color textColor: (kind === "primary") ? "#1e2326" : cFg
        signal clicked()
        radius: 12; implicitHeight: 36
        scale: pressed ? 0.95 : (hovered && !disabled ? 1.045 : 1.0)
        readonly property bool hovered: btnMouse.containsMouse
        readonly property bool pressed: btnMouse.pressed
        color: {
            if (kind === "primary") return disabled ? Qt.rgba(btnColor.r, btnColor.g, btnColor.b, 0.35) : (hovered ? Qt.darker(btnColor, 1.1) : btnColor)
            if (kind === "ghost") return hovered ? Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.10) : "transparent"
            return hovered ? Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.10) : "transparent"
        }
        border.width: (kind === "primary" || kind === "ghost") ? 0 : 1
        border.color: { if (kind === "primary") return "transparent"; return hovered ? Qt.rgba(cBlue.r, cBlue.g, cBlue.b, 0.35) : cBorder }
        opacity: disabled ? 0.55 : 1.0
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 120 } }
        RowLayout {
            anchors.centerIn: parent; spacing: 8
            Text { visible: btn.icon.length > 0; text: btn.icon; font.family: fontIcon; font.pixelSize: 14; color: btn.textColor }
            Text { text: btn.text; font.family: fontText; font.pixelSize: 12; font.weight: Font.Bold; color: btn.textColor }
        }
        MouseArea {
            id: btnMouse; anchors.fill: parent; hoverEnabled: true
            cursorShape: btn.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor; enabled: !btn.disabled
            onClicked: btn.clicked()
        }
    }

    component PillField: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder: ""
        property int echoMode: TextInput.Normal
        property bool enabled: true
        signal accepted()
        Layout.preferredHeight: 38; radius: 999
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1; border.color: input.activeFocus ? Qt.rgba(cGreen.r, cGreen.g, cGreen.b, 0.7) : cBorder
        opacity: enabled ? 1.0 : 0.6; clip: true
        TextInput {
            id: input; anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
            enabled: field.enabled; color: cFg; font.family: fontText; font.pixelSize: 13
            echoMode: field.echoMode; verticalAlignment: TextInput.AlignVCenter; selectByMouse: true
            Keys.onReturnPressed: field.accepted()
        }
        Text {
            anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
            text: field.placeholder; color: cMuted; font.family: fontText; font.pixelSize: 13
            visible: input.text.length === 0 && !input.activeFocus
        }
        MouseArea { anchors.fill: parent; enabled: field.enabled; cursorShape: Qt.IBeamCursor; onClicked: input.forceActiveFocus() }
    }
}
