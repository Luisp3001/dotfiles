// shell.qml — Punto de entrada principal del entorno Quickshell
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.DBusMenu
import "core/bar"
import "components" as Components
import "core/HyprQuickFrame"
import "core/notifications"


ShellRoot {
    id: shell

    // ── Shared Notification Service ────────────────────────────────────
    property var notifServer: NotificationServer {
        actionsSupported: true
        keepOnReload: true
        imageSupported: true
        bodyImagesSupported: true
    }

    property var notifHandler: NotificationHandler {
        server: shell.notifServer
        dndEnabled: false
    }

    property var notifHistory: NotifHistoryModel {
        server: shell.notifServer
    }

    // Estado global de la Isla Dinámica
    property bool launcherOpen: false
    property bool notifOpen: false
    property bool wallpaperOpen: false
    property bool airdropOpen: false
    property bool pluginInstallOpen: false
    property var activeDynamicWidget: null
    property bool screenshotActive: false
    
    // Propiedad derivada que centraliza si la isla está expandida por CUALQUIER motivo (incluyendo futuros plugins dinámicos)
    property bool isIslandExpanded: launcherOpen || notifOpen || wallpaperOpen || airdropOpen || pluginInstallOpen || activeDynamicWidget !== null

    // Función para cerrar cualquier panel/widget abierto
    function closeIsland() {
        launcherOpen = false;
        notifOpen = false;
        wallpaperOpen = false;
        airdropOpen = false;
        pluginInstallOpen = false;
        activeDynamicWidget = null;
    }

    // Helper para alternar un panel y cerrar los demás
    function togglePanel(panelType) {
        let wasOpen = false;
        if (panelType === "launcher") wasOpen = shell.launcherOpen;
        else if (panelType === "notif") wasOpen = shell.notifOpen;
        else if (panelType === "wallpaper") wasOpen = shell.wallpaperOpen;
        else if (panelType === "pluginInstall") wasOpen = shell.pluginInstallOpen;
        
        shell.closeIsland();
        
        if (!wasOpen) {
            if (panelType === "launcher") shell.launcherOpen = true;
            else if (panelType === "notif") shell.notifOpen = true;
            else if (panelType === "wallpaper") shell.wallpaperOpen = true;
            else if (panelType === "pluginInstall") shell.pluginInstallOpen = true;
        }
    }
    property alias pluginManager: pluginMgr

    // ── Global Signals ───────────────────────────────────────────────────
    signal globalFileDropped(var paths)

    // ── OSD State (Volume/Brightness) ──────────────────────────────────
    property string osdType: ""       // "" | "volume" | "brightness"
    property int    osdValue: 0       // 0–100
    property string osdIcon: ""       // Nerd Font icon

    // ── Volume Monitoring (Pipewire) ───────────────────────────────────
    property int _lastVolume: -1

    // Tracker necesario para que Quickshell mantenga el nodo enlazado y
    // sus propiedades (volume, muted) reciban actualizaciones de Pipewire.
    PwObjectTracker {
        id: defaultSinkTracker
        objects: [Pipewire.defaultAudioSink]
    }

    // Escucha cambios en el sink por defecto (ej. cuando el usuario cambia de
    // salida de audio) y reconfigura las Connections al nuevo nodo de audio.
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            shell._lastVolume = -1;  // Forzar re-inicialización con el nuevo sink
        }
    }

    // Escucha cambios de volumen y mute directamente desde PwNodeAudio.
    // Pipewire.defaultAudioSink?.audio es el objeto correcto tras el tracking.
    Connections {
        target: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
        function onVolumesChanged() { shell._handleVolumeChange(); }
        function onMutedChanged()   { shell._handleVolumeChange(); }
    }

    function _handleVolumeChange() {
        var sinkAudio = Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null;
        if (!sinkAudio) return;

        var vol   = Math.round(sinkAudio.volume * 100);
        var muted = sinkAudio.muted;
        var desc  = Pipewire.defaultAudioSink ? (Pipewire.defaultAudioSink.description || "") : "";
        var isHp  = desc.toLowerCase().includes("headphone") ||
                    desc.toLowerCase().includes("auricular");

        // Solo mostrar OSD si el valor realmente cambió (evitar el primer arranque)
        if (shell._lastVolume >= 0 && vol !== shell._lastVolume) {
            var icon;
            if (muted || vol === 0) icon = "\u{F0581}";   // mute
            else if (vol > 50)      icon = "\u{F057E}";   // vol high
            else                    icon = "\u{F0580}";   // vol low

            shell.osdType  = "volume";
            shell.osdValue = vol;
            shell.osdIcon  = icon;
            osdHideTimer.restart();
        }
        shell._lastVolume = vol;
    }

    // ── Brightness Monitoring ──────────────────────────────────────────
    property int _lastBrightness: -1
    property var _briMonProcess: Process {
        command: ["bash", "-lc", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '% ' || true"]
        stdout: SplitParser {
            onRead: function(line) {
                var val = parseInt(String(line).trim());
                if (!isFinite(val)) return;
                if (shell._lastBrightness >= 0 && val !== shell._lastBrightness) {
                    var icon;
                    if (val < 30)       icon = "\u{F00DF}";  // brightness low
                    else if (val < 70)  icon = "\u{F00E0}";  // brightness med
                    else                icon = "\u{F00E1}";  // brightness high
                    shell.osdType = "brightness";
                    shell.osdValue = val;
                    shell.osdIcon = icon;
                    osdHideTimer.restart();
                }
                shell._lastBrightness = val;
            }
        }
    }

    Timer {
        id: briMonPoll
        interval: 500
        running: true; repeat: true
        onTriggered: {
            if (!shell._briMonProcess.running)
                shell._briMonProcess.running = true;
        }
    }

    // ── OSD Auto-Hide Timer ────────────────────────────────────────────
    Timer {
        id: osdHideTimer
        interval: 2000
        onTriggered: shell.osdType = ""
    }

    // ── System Metrics (for compact bar + SystemWidget) ────────────────
    property int sysCpu: 0
    property string sysRamUsed: "0"
    property string sysRamTotal: "0"
    property int sysRamPercent: 0
    property int sysTemp: 0
    property int sysUptime: 0

    property var _sysMetricsProcess: Process {
        command: ["bash", "-c", "read _ a1 b1 c1 d1 _ < /proc/stat; sleep 0.2; read _ a2 b2 c2 d2 _ < /proc/stat; dt=$((a2+b2+c2+d2-a1-b1-c1-d1)); di=$((d2-d1)); if [ \"$dt\" -gt 0 ]; then cpu=$((100*(dt-di)/dt)); else cpu=0; fi; eval $(awk '/MemTotal/{printf \"mt=%d;\", $2} /MemAvailable/{printf \"ma=%d;\", $2}' /proc/meminfo); mu=$((mt-ma)); rp=$((mu*100/mt)); rg=$(awk \"BEGIN{printf \\\"%.1f\\\", $mu/1048576}\"); rtg=$(awk \"BEGIN{printf \\\"%.1f\\\", $mt/1048576}\"); temp=0; for f in /sys/class/thermal/thermal_zone*; do if [ \"$(cat \"$f/type\" 2>/dev/null)\" = \"x86_pkg_temp\" ]; then t=$(cat \"$f/temp\" 2>/dev/null); temp=$((t/1000)); break; fi; done; if [ \"$temp\" -eq 0 ]; then t=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | head -1); if [ -n \"$t\" ]; then temp=$((t/1000)); fi; fi; up=$(awk '{printf \"%d\", $1}' /proc/uptime); echo \"$cpu|$rg|$rtg|$rp|$temp|$up\""]
        stdout: SplitParser {
            onRead: function(line) {
                var parts = String(line).trim().split("|");
                if (parts.length < 6) return;
                shell.sysCpu = parseInt(parts[0]) || 0;
                shell.sysRamUsed = parts[1] || "0";
                shell.sysRamTotal = parts[2] || "0";
                shell.sysRamPercent = parseInt(parts[3]) || 0;
                shell.sysTemp = parseInt(parts[4]) || 0;
                shell.sysUptime = parseInt(parts[5]) || 0;
            }
        }
    }

    Timer {
        id: sysMetricsPoll
        interval: 3000
        running: true; repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!shell._sysMetricsProcess.running)
                shell._sysMetricsProcess.running = true;
        }
    }

    // Screen recording state
    property string screenRecState: "idle"
    property int screenRecElapsed: 0
    property var _pendingRecArgs: []
    property int activeWidget: 0

    readonly property string screenRecScript: Quickshell.env("HOME") + "/.config/quickshell/optional/screenrec/wl_screenrec_ctl.sh"

    function screenRecRunCtl(action) {
        Quickshell.execDetached(["bash", screenRecScript, action]);
    }

    function screenRecStartFullscreen(extraPluginArgs) {
        shell.notifOpen = false;
        var argsToPass = shell._pendingRecArgs.slice();
        if (extraPluginArgs && extraPluginArgs.length > 0) {
            argsToPass = argsToPass.concat(extraPluginArgs);
        }
        var cmd = ["bash", screenRecScript, "start", "--"].concat(argsToPass);
        Quickshell.execDetached(cmd);
    }

    function screenRecStartRegion(extraPluginArgs) {
        shell.notifOpen = false;
        var argsToPass = shell._pendingRecArgs.slice();
        if (extraPluginArgs && extraPluginArgs.length > 0) {
            argsToPass = argsToPass.concat(extraPluginArgs);
        }
        var extraArgsStr = argsToPass.map(function(a) {
            return "'" + String(a).replace(/'/g, "'\\''") + "'";
        }).join(" ");
        var script = "sleep 0.4; geo=$(slurp) && exec bash '" + shell.screenRecScript + "' start -- " + extraArgsStr + " --geometry \"$geo\"";
        Quickshell.execDetached(["bash", "-c", script]);
    }

    Components.CommandPoll {
        id: screenRecPoll
        interval: (shell.screenRecState === "recording" || shell.screenRecState === "paused") ? 500 : 3000
        command: ["bash", shell.screenRecScript, "status"]
        parse: function(out) { return String(out ?? "").trim(); }
        onUpdated: {
            try {
                var o = JSON.parse(screenRecPoll.text || "{}");
                shell.screenRecState = o.state || "idle";
                if (typeof o.elapsed_sec === "number")
                    shell.screenRecElapsed = Math.floor(o.elapsed_sec);
                else
                    shell.screenRecElapsed = parseInt(o.elapsed_sec, 10) || 0;

                if (o.pending_open === true && shell.screenRecState === "idle") {
                    shell._pendingRecArgs = Array.isArray(o.pending_args) ? o.pending_args : [];
                    
                    if (shell.pluginManager) {
                        var plugins = shell.pluginManager.activeWidgets;
                        for (var i = 0; i < plugins.length; i++) {
                            if (plugins[i].pluginId === "com.luisp.screenrec") {
                                shell.activeDynamicWidget = plugins[i];
                                break;
                            }
                        }
                    }
                    shell.notifOpen = false;
                }
            } catch (e) {
                shell.screenRecState = "idle";
                shell.screenRecElapsed = 0;
            }
        }
    }

    // IPC Handler para escuchar comandos desde Hyprland
    // Uso: quickshell ipc call shell toggleLauncher
    IpcHandler {
        target: "shell"
        function toggleLauncher(): void { shell.togglePanel("launcher") }
        function toggleNotif(): void { shell.togglePanel("notif") }
        function toggleWallpaper(): void { shell.togglePanel("wallpaper") }
        function launchScreenshot(): void {
            shell.screenshotActive = true;
        }
    }

    // Instanciamos los elementos por cada pantalla disponible
    Variants {
        model: Quickshell.screens

        // Usamos un QtObject como contenedor para crear múltiples ventanas por pantalla
        QtObject {
            required property var modelData

            // 1. Ventana invisible para reservar espacio exclusivo en la pantalla
            // Mantiene el resto de ventanas de Hyprland abajo sin empujarlas cuando la isla se expanda
            property var spaceReservation: PanelWindow {
                screen: modelData
                anchors { top: true; left: true; right: true }
                implicitHeight: 36 // Solo reservamos el espacio de la barra superior
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Top
                mask: Region {} // <-- MAGIA: con una región vacía todos los clicks la traspasan
            }

            property var dismissOverlay: PanelWindow {
                screen: modelData
                anchors { top: true; bottom: true; left: true; right: true }
                visible: shell.isIslandExpanded
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.exclusionMode: WlrLayershell.Ignore
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: shell.closeIsland()
                }
            }

            // 3. Ventana principal (la barra y la Isla Dinámica)
            property var mainWindow: PanelWindow {
                id: mainWin
                screen: modelData
                // La ventana ahora abarca TODA la pantalla fijamente para evitar recalcular su geometría en Wayland
                anchors { top: true; bottom: true; left: true; right: true }
                color: "transparent"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.exclusionMode: WlrLayershell.Exclusive
                WlrLayershell.keyboardFocus: shell.isIslandExpanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                // La magia: solo la región del 'bar' aceptará eventos, el resto pasará de largo (o caerá en dismissOverlay si está abierto)
                mask: Region {
                    item: bar
                }

                Bar {
                    id: bar
                    // Se ancla al centro de la ventana completa
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    shellRoot: shell
                    pluginManager: shell.pluginManager
                    isLauncherExpanded: shell.launcherOpen
                    isNotifExpanded: shell.notifOpen
                    isWallpaperExpanded: shell.wallpaperOpen
                    isPluginInstallExpanded: shell.pluginInstallOpen
                    activeDynamicWidget: shell.activeDynamicWidget
                    
                    onToggleLauncherExpanded: shell.togglePanel("launcher")
                    onToggleNotifExpanded: shell.togglePanel("notif")
                    onToggleWallpaperExpanded: shell.togglePanel("wallpaper")
                    onTogglePluginInstall: shell.togglePanel("pluginInstall")

                    // Escuchamos la señal del SystemTray para abrir el menú contextual
                    onTrayMenuRequested: (trayItem, gx, gy) => {
                        trayMenuWin.openMenu(trayItem, gx, gy);
                    }
                }
            }

            // 4. Ventana popup para el menú del System Tray
            // Debe ser hijo del mismo scope que mainWindow para tener acceso al PanelWindow real
            property var trayMenuWindow: PopupWindow {
                id: trayMenuWin
                visible: false
                color: "transparent"

                // Anclamos al mainWindow real (PanelWindow), no al ProxiedWindow
                anchor.window: mainWin
                anchor.rect.x: _trayMenuX
                anchor.rect.y: _trayMenuY
                anchor.rect.width: 1
                anchor.rect.height: 1

                implicitWidth: trayMenuCol.implicitWidth + 20
                implicitHeight: trayMenuCol.implicitHeight + 20

                property real _trayMenuX: 0
                property real _trayMenuY: 0

                // Opener de menú DBus
                QsMenuOpener {
                    id: trayMenuOpener
                    menu: null
                }

                // Auto-ocultar cuando el ratón sale
                Timer {
                    id: trayHideTimer
                    interval: 700
                    running: false
                    repeat: false
                    onTriggered: trayMenuWin.visible = false
                }

                function openMenu(trayItem, gx, gy) {
                    trayMenuOpener.menu = null;
                    trayMenuOpener.menu = trayItem.menu;
                    _trayMenuX = gx;
                    _trayMenuY = gy + 8;
                    visible = true;
                    trayHideTimer.stop();
                }

                // Fondo del menú
                Rectangle {
                    anchors.fill: parent
                    color: "#1a1a1a"
                    radius: 12
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1
                    clip: true
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: trayHideTimer.stop()
                    onExited: trayHideTimer.restart()
                }

                // Ítems del menú
                ColumnLayout {
                    id: trayMenuCol
                    spacing: 3
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 10
                    }

                    Repeater {
                        model: trayMenuOpener.children

                        delegate: Rectangle {
                            id: mItem
                            required property QsMenuEntry modelData

                            Layout.fillWidth: true
                            implicitHeight: modelData.isSeparator ? 9 : 32
                            implicitWidth: mLabel.implicitWidth + 36
                            radius: 8
                            color: mHover.containsMouse
                                ? Qt.rgba(1, 1, 1, 0.1)
                                : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: 110 }
                            }

                            // Separador
                            Rectangle {
                                visible: modelData.isSeparator
                                anchors.centerIn: parent
                                width: parent.width - 12
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.1)
                            }

                            // Ícono del ítem
                            Image {
                                id: mIcon
                                visible: !modelData.isSeparator && source.toString() !== ""
                                source: modelData.icon ?? ""
                                width: 16; height: 16
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                smooth: true; mipmap: true
                            }

                            // Texto del ítem
                            Text {
                                id: mLabel
                                visible: !modelData.isSeparator
                                anchors {
                                    left: mIcon.visible ? mIcon.right : parent.left
                                    leftMargin: mIcon.visible ? 6 : 10
                                    right: parent.right
                                    rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modelData.text ?? ""
                                color: modelData.enabled === false
                                    ? Qt.rgba(1, 1, 1, 0.35)
                                    : "#e0e0e0"
                                font.pixelSize: 13
                                font.family: "Inter"
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: mHover
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !modelData.isSeparator && modelData.enabled !== false
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onEntered: trayHideTimer.stop()
                                onExited: trayHideTimer.restart()
                                onClicked: {
                                    modelData.triggered();
                                    trayMenuWin.visible = false;
                                }
                            }
                        }
                    }
                }
            }
            
            // ── Notification OSD (Overlay Layer) ────
            property var notificationOsd: PanelWindow {
                screen: modelData
                anchors { top: true; right: true }
                implicitWidth: 350
                implicitHeight: notifOsd.height + 20
                margins.top: 10
                margins.right: 10
                color: "transparent"
                visible: shell.notifHandler.active
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell"

                Rectangle {
                    id: notifOsd
                    width: parent.width
                    height: Math.min(notifContent.implicitHeight + 32, 140)
                    color: "#1c1c1c"
                    radius: 12
                    border.color: "#333333"
                    border.width: 1
                    clip: true

                    // Swipe offset for dismiss gesture
                    property real swipeX: 0
                    transform: Translate { x: notifOsd.swipeX }
                    opacity: 1.0 - Math.min(Math.abs(notifOsd.swipeX) / 200, 0.8)

                    Behavior on swipeX {
                        id: swipeReturnBehavior
                        enabled: false
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    NotificationContent {
                        id: notifContent
                        anchors.fill: parent
                        anchors.margins: 16
                        anchors.rightMargin: 36 // space for close button
                        rootWidget: shell
                    }

                    // Close button
                    Rectangle {
                        id: osdCloseBtn
                        width: 24; height: 24; radius: 12
                        color: osdCloseMa.containsMouse
                            ? Qt.rgba(1, 0, 0, 0.25)
                            : Qt.rgba(1, 1, 1, 0.08)
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.margins: 8
                        z: 10

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: osdCloseMa.containsMouse ? "#f38ba8" : "#6c7086"
                            font.pixelSize: 11; font.weight: Font.Bold
                        }

                        MouseArea {
                            id: osdCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shell.notifHandler.dismiss()
                        }
                    }

                    // Swipe / drag to dismiss
                    MouseArea {
                        id: swipeArea
                        anchors.fill: parent
                        z: 5
                        propagateComposedEvents: true
                        property real startX: 0
                        property bool dragging: false

                        onPressed: (mouse) => {
                            startX = mouse.x;
                            dragging = false;
                            swipeReturnBehavior.enabled = false;
                        }
                        onPositionChanged: (mouse) => {
                            var dx = mouse.x - startX;
                            // Only allow swipe right (positive direction)
                            if (dx > 10 || dragging) {
                                dragging = true;
                                notifOsd.swipeX = Math.max(0, dx);
                            }
                        }
                        onReleased: (mouse) => {
                            if (dragging && notifOsd.swipeX > 100) {
                                // Dismiss: animate out
                                swipeReturnBehavior.enabled = true;
                                notifOsd.swipeX = 400;
                                dismissAfterSwipe.start();
                            } else {
                                // Snap back
                                swipeReturnBehavior.enabled = true;
                                notifOsd.swipeX = 0;
                            }
                            dragging = false;
                        }
                        // Pass through clicks to close button
                        onClicked: (mouse) => {
                            if (!dragging) mouse.accepted = false;
                        }
                    }

                    Timer {
                        id: dismissAfterSwipe
                        interval: 220
                        onTriggered: {
                            shell.notifHandler.dismiss();
                            notifOsd.swipeX = 0;
                        }
                    }
                }
            }
        }
    }

    // ── PluginManager ────────────────────────────────────────────────────
    Components.PluginManager {
        id: pluginMgr
        shellRoot: shell
    }

    // ── HyprQuickFrame / Screenshot Tool (SUPER+SHIFT+S) ──────────────
    ScreenshotTool {
        active: shell.screenshotActive
        onDone: shell.screenshotActive = false
    }
}
