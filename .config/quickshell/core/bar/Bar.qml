// modules/bar/Bar.qml — Módulo central del bar (el "Dynamic Island")
import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Io
import "."
import "../../style"
import "../../components"
import "../../optional/screenrec"

Item {
    id: root

    property var shellRoot: null
    property var pluginManager: null

    // Estado para saber si el App Launcher está abierto
    property bool isLauncherExpanded: false
    signal toggleLauncherExpanded()

    // Estado para saber si el Notification Center está abierto
    property bool isNotifExpanded: false
    signal toggleNotifExpanded()

    // Estado para saber si el Wallpaper Picker está abierto
    property bool isWallpaperExpanded: false
    signal toggleWallpaperExpanded()

    // Estado para Plugin Install (drag & drop)
    property bool isPluginInstallExpanded: false
    signal togglePluginInstall()
    property bool pluginDropMode: false
    property var pluginManifest: ({})
    property string pluginSourcePath: ""

    // Estado para arrastrar y soltar archivos (Hover global)
    property bool isFileHovered: false

    // ── Dynamic Widgets ──
    property var activeDynamicWidget: null
    property bool isCenterExpanded: isNotifExpanded || activeDynamicWidget !== null

    onActiveDynamicWidgetChanged: {
        if (activeDynamicWidget !== null && centerSection) {
            for (var i = 0; i < centerSection.centerWidgets.length; i++) {
                if (centerSection.centerWidgets[i].pluginId === activeDynamicWidget.pluginId) {
                    centerSection.currentTabIndex = i + 1;
                    break;
                }
            }
        }
    }

    function toggleDynamicWidget(widgetObj) {
        if (shellRoot) {
            if (shellRoot.activeDynamicWidget === widgetObj) {
                shellRoot.activeDynamicWidget = null;
            } else {
                shellRoot.activeDynamicWidget = widgetObj;
                shellRoot.launcherOpen = false;
                shellRoot.notifOpen = false;
                shellRoot.wallpaperOpen = false;
                shellRoot.pluginInstallOpen = false;
            }
        }
    }

    // Señal del menú del System Tray — reenviada desde RightSection → shell.qml
    signal trayMenuRequested(var trayItem, real globalX, real globalY)

    // activeWidget ya no se utiliza porque todos los módulos son plugins dinámicos.

    // Ancho real de cada lado (incluyendo márgenes y todos los elementos visibles)
    // Lado izquierdo: leftSection + margen izquierdo (20) + gap interno (12)
    property int leftSideWidth: leftSection.implicitWidth + 32
    // Lado derecho: rightSection + margen derecho (20) + dynamicWidgetsRow + su spacing (12) + gap (12)
    property int rightSideWidth: rightSection.implicitWidth + 80 + (dynamicWidgetsRow.implicitWidth > 0 ? dynamicWidgetsRow.implicitWidth + 8 : 0)

    // El margen simétrico usa el lado más ancho para que el centro quede perfectamente centrado
    property int symmetricSideWidth: Math.max(leftSideWidth, rightSideWidth)

    // Ancho base estándar: ambos lados simétricos + ancho del contenido central
    property int normalBaseWidth: (symmetricSideWidth * 2) + centerSection.implicitWidth

    // Ancho de la sección central (ahora siempre el reloj)
    property int activeCenterWidth: centerSection.implicitWidth

    // Ancho base cuando está cerrada
    property int baseIslandWidth: normalBaseWidth
    
    // Ancho extendido al abrir el Notification Center, Launcher o Wallpaper
    property int targetWidth: {
        if (isFileHovered) return 300
        if (isWallpaperExpanded) return 1100
        if (isLauncherExpanded) return normalBaseWidth + 200
        if (isPluginInstallExpanded) return 400
        if (activeDynamicWidget !== null) return activeDynamicWidget.expandedWidth || 400
        if (!isNotifExpanded) return baseIslandWidth
        
        // Tab 0 = Panel principal con secciones
        if (notifCenter.currentSection === 0) return 400 // Notificaciones + DND
        if (notifCenter.currentSection === 1) return 400 // WiFi
        if (notifCenter.currentSection === 2) return 400 // Bluetooth
        if (notifCenter.currentSection === 3) return 400 // Power Menu
        if (notifCenter.currentSection === 4) return 500 // Plugins
        
        return Math.max(normalBaseWidth + 60, 350)
    }
    // Altura del Notification Center, Launcher o Wallpaper
    property int targetHeight: {
        if (isFileHovered) return 160
        if (isWallpaperExpanded) return 550
        if (isLauncherExpanded) return 500
        if (isPluginInstallExpanded) return (pluginInstallContent.preferredHeight + Theme.barHeight + 12)
        if (activeDynamicWidget !== null) return (activeDynamicWidget.expandedHeight || 200) + Theme.barHeight + 12 + 42
        if (!isNotifExpanded) return Theme.barHeight
        // Tab 0 = Panel principal con secciones
        if (notifCenter.currentSection === 0) return 500 + 42 // Notificaciones + DND
        if (notifCenter.currentSection === 1) return 600 + 42 // WiFi
        if (notifCenter.currentSection === 2) return 600 + 42 // Bluetooth
        if (notifCenter.currentSection === 3) return 455 + 42 // Power Menu
        if (notifCenter.currentSection === 4) return 450 + 42 // Plugins
        return 500 + 42
    }

    // Proveemos el tamaño exacto del root para que la máscara (Region) se ajuste perfecto
    width: island.width
    height: island.height

    // Contenedor principal de la isla
    Item {
        id: island
        width: root.targetWidth
        height: root.targetHeight
        anchors.top: parent.top
        // Ya no necesitamos horizontalCenter porque Bar ya está centrado en shell.qml y tienen el mismo ancho
        // Animaciones suaves y rebotantes estilo Dynamic Island
        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }
        Behavior on height { NumberAnimation { duration: 350; easing.type: Easing.OutExpo } }

        // Cuerpo principal de la Isla (Negro Sólido)
        // Usa radios individuales por esquina: recto arriba (se fusiona con la pantalla),
        // redondeado abajo (estilo Dynamic Island)
        Rectangle {
            id: islandBody
            anchors.fill: parent
            color: "#000000"
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: 30
            bottomRightRadius: 30
            clip: true // Esencial para evitar que el launcher dibuje fuera de las esquinas curvas

            // Catch-all MouseArea to prevent clicks on the island from closing it
            MouseArea {
                anchors.fill: parent
                // hoverEnabled no es necesario, solo queremos atrapar los clics
                onClicked: {} 
            }

            // ── DropArea Global para Plugins y Archivos ──
            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list", "text/plain"]
                
                onEntered: { root.isFileHovered = true; }
                onExited: { root.isFileHovered = false; }
                onDropped: (drop) => {
                    root.isFileHovered = false;
                    if (drop.hasUrls) {
                        var paths = []
                        for (var i = 0; i < drop.urls.length; i++) {
                            var url = drop.urls[i].toString().trim()
                            if (url.startsWith("file://")) {
                                paths.push(decodeURIComponent(url.replace("file://", "")))
                            }
                        }
                        if (paths.length === 1) {
                            // Single path — check if it's a plugin folder
                            root.pluginSourcePath = paths[0]
                            pluginCheckProc.manifestText = ""
                            pluginCheckProc.command = ["bash", "-c",
                                "test -d '" + paths[0] + "' && test -f '" + paths[0] + "/plugin.json' && cat '" + paths[0] + "/plugin.json'"]
                            pluginCheckProc.running = true
                        } else if (paths.length > 0) {
                            // Multiple files → always emit global dropped signal
                            root.pluginDropMode = false
                            if (root.shellRoot) {
                                root.shellRoot.globalFileDropped(paths);
                            }
                        }
                    }
                    drop.acceptProposedAction()
                }
            }

            // ── Contenido Expandido (File Hover) ──
            Item {
                id: fileHoverContent
                anchors {
                    top: parent.top
                    topMargin: Theme.barHeight
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                
                opacity: root.isFileHovered ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 12
                    radius: 16
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.1)

                    Column {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ""
                            font.family: Theme.fontMono
                            font.pixelSize: 32
                            color: Theme.accent
                            opacity: 0.8
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Drop file here"
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.fontSizeMd
                            color: Theme.textPrimary
                            opacity: 0.8
                        }
                    }
                }
            }

            // ── Contenido Expandido (App Launcher) ──
            Item {
                id: expandedLauncher
                anchors {
                    top: parent.top
                    topMargin: Theme.barHeight // Se posiciona justo debajo de la barra
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                
                opacity: root.isLauncherExpanded ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                AppLauncher {
                    id: appLauncher
                    anchors.fill: parent
                    anchors.margins: 12
                    rootWidget: root
                }
                
                // Si la isla se abre, reseteamos/enfocamos el launcher
                Connections {
                    target: root
                    function onIsLauncherExpandedChanged() {
                        if (root.isLauncherExpanded) {
                            appLauncher.reload();
                        }
                    }
                }
            }

            // ── Contenido Expandido (Notification Center) ──
            Item {
                id: expandedNotif
                anchors {
                    top: parent.top
                    topMargin: Theme.barHeight + 42 // Se posiciona debajo de la barra y el global tab bar
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                // Desvanecer el panel al cerrar
                opacity: root.isNotifExpanded ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                NotificationCenter {
                    id: notifCenter
                    anchors.fill: parent
                    shellRoot: root.shellRoot
                }
            }

            // ── Contenido Expandido (Wallpaper Picker) ──
            Item {
                id: expandedWallpaper
                anchors {
                    top: parent.top
                    topMargin: Theme.barHeight
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                
                opacity: root.isWallpaperExpanded ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                WallpaperPicker {
                    id: wallpaperPicker
                    anchors.fill: parent
                    shellRoot: root.shellRoot
                }
            }

            // ── Contenido Expandido (Plugin Install) ──
            Item {
                id: expandedPluginInstall
                anchors {
                    top: parent.top
                    topMargin: Theme.barHeight
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                
                opacity: root.isPluginInstallExpanded ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                PluginInstallContent {
                    id: pluginInstallContent
                    anchors.fill: parent
                    anchors.margins: 12
                    rootWidget: root
                    pluginManager: root.pluginManager
                    visible: true
                }
            }

            // ── Dynamic Widget Panels ──
            Repeater {
                model: root.pluginManager ? root.pluginManager.activeWidgets : []
                delegate: Item {
                    anchors {
                        top: parent.top
                        topMargin: Theme.barHeight + 42
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    
                    opacity: root.activeDynamicWidget === modelData ? 1.0 : 0.0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                    Loader {
                        id: dynamicPanelLoader
                        anchors.fill: parent
                        anchors.margins: 12
                        sourceComponent: root.activeDynamicWidget === modelData ? modelData.expandedPanel : null
                        property var rootWidget: root
                        property var shellRoot: root.shellRoot

                        onLoaded: {
                            // Push shellRoot into the plugin widget immediately upon load.
                            // Context properties from the Loader are not reliably bindable
                            // inside nested children of the loaded component.
                            if (modelData && root.shellRoot) {
                                modelData.shellRoot = root.shellRoot;
                                modelData.rootWidget = root;
                            }
                        }
                    }
                }
            }

            // ── Global Tab Bar ──
            Item {
                id: globalTabBar
                anchors {
                    top: parent.top
                    topMargin: Theme.barHeight + 4
                    left: parent.left
                    right: parent.right
                }
                height: 38
                opacity: root.isCenterExpanded ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                property int pluginCount: centerSection.centerWidgets.length
                property int totalTabCount: pluginCount + 2  // notif + plugins + plugins_manager

                Item {
                    id: tabsItem
                    width: Math.max(42, globalTabBar.totalTabCount * 46 - 4)
                    height: 30
                    anchors.centerIn: parent

                    // ── Tab: Notifications (fixed first, slot 0) ──
                    Rectangle {
                        id: notifGlobalTab
                        x: 0; width: 42; height: 30; radius: 8
                        color: centerSection.currentTabIndex === 0
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                            : (notifGlobalTabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors.centerIn: parent; text: "\u{F0009}"
                            color: centerSection.currentTabIndex === 0 ? Theme.accent : Theme.textMuted
                            font.family: Theme.fontMono; font.pixelSize: 15
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            id: notifGlobalTabMouse; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: {
                                if (centerSection.currentTabIndex === 0 && root.isNotifExpanded) {
                                    root.toggleNotifExpanded();
                                } else {
                                    centerSection.currentTabIndex = 0;
                                    notifCenter.currentSection = 0;
                                    if (root.shellRoot) {
                                        root.shellRoot.notifOpen = true;
                                        root.shellRoot.activeDynamicWidget = null;
                                    }
                                }
                            }
                        }
                    }

                    // ── Plugin Tabs (reorderable via drag & drop, slots 1..N) ──
                    Repeater {
                        id: pluginsRepeater
                        model: centerSection.centerWidgets
                        delegate: Rectangle {
                            id: pluginTab
                            width: 42; height: 30; radius: 8
                            z: 1

                            property int naturalSlot: index + 1

                            x: naturalSlot * 46
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                            color: centerSection.currentTabIndex === index + 1
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                : (pluginTabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: (modelData.tabIcon !== undefined) ? modelData.tabIcon : (modelData.type === "window" ? "󰖲" : "󰏗")
                                color: centerSection.currentTabIndex === index + 1 ? Theme.accent : Theme.textMuted
                                font.family: Theme.fontMono; font.pixelSize: 18
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                id: pluginTabMouse; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    if (centerSection.currentTabIndex === index + 1 && root.activeDynamicWidget === modelData) {
                                        root.toggleDynamicWidget(modelData);
                                    } else {
                                        centerSection.currentTabIndex = index + 1;
                                        if (root.shellRoot) {
                                            root.shellRoot.notifOpen = false;
                                            root.shellRoot.activeDynamicWidget = modelData;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Tab: Plugins Manager (fixed last, slot N+1) ──
                    Rectangle {
                        id: pluginsGlobalTab
                        x: (globalTabBar.pluginCount + 1) * 46
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                        width: 42; height: 30; radius: 8
                        z: 1
                        property int myTabIndex: centerSection.centerWidgets.length + 1
                        color: centerSection.currentTabIndex === myTabIndex
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                            : (pluginsGlobalTabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors.centerIn: parent; text: "󰏗"
                            color: centerSection.currentTabIndex === pluginsGlobalTab.myTabIndex ? Theme.accent : Theme.textMuted
                            font.family: Theme.fontMono; font.pixelSize: 18
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            id: pluginsGlobalTabMouse; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor; onClicked: {
                                var pmIdx = centerSection.centerWidgets.length + 1;
                                if (centerSection.currentTabIndex === pmIdx && root.isNotifExpanded) {
                                    root.toggleNotifExpanded();
                                } else {
                                    centerSection.currentTabIndex = pmIdx;
                                    notifCenter.currentSection = 4;
                                    if (root.shellRoot) {
                                        root.shellRoot.notifOpen = true;
                                        root.shellRoot.activeDynamicWidget = null;
                                    }
                                }
                            }
                        }
                    }
                }

                // Indicador activo
                Rectangle {
                    id: globalTabIndicator
                    height: 2; width: 24; radius: 1; color: Theme.accent
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                    x: {
                        var activeIdx = centerSection.currentTabIndex;
                        var pmIdx = centerSection.centerWidgets.length + 1;
                        if (activeIdx === 0) {
                            return tabsItem.x + notifGlobalTab.x + (notifGlobalTab.width - width) / 2;
                        } else if (activeIdx === pmIdx) {
                            return tabsItem.x + pluginsGlobalTab.x + (pluginsGlobalTab.width - width) / 2;
                        } else if (activeIdx >= 1 && activeIdx <= centerSection.centerWidgets.length) {
                            var rect = pluginsRepeater.itemAt(activeIdx - 1);
                            if (rect) {
                                return tabsItem.x + rect.x + (rect.width - width) / 2;
                            }
                        }
                        return 0;
                    }
                    Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                }

                // Separador
                Rectangle {
                    width: parent.width - 24; height: 1
                    anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.accentDim; opacity: 0.2
                }
            }
        }


        // ── Plugin detection process ─────────────────────────────────
        // Checks if dropped folder contains plugin.json
        Process {
            id: pluginCheckProc
            property string manifestText: ""

            stdout: SplitParser {
                splitMarker: "\n"
                onRead: (line) => {
                    pluginCheckProc.manifestText += line + "\n"
                }
            }

            onExited: (code) => {
                if (code === 0 && pluginCheckProc.manifestText.trim() !== "") {
                    try {
                        var manifest = JSON.parse(pluginCheckProc.manifestText)
                        // Plugin detected!
                        root.pluginDropMode = true
                        root.pluginManifest = manifest
                        pluginInstallContent.setPlugin(root.pluginSourcePath, manifest)
                        if (!root.isPluginInstallExpanded) {
                            root.togglePluginInstall()
                        }
                    } catch (e) {
                        // Invalid JSON → treat as normal file
                        root.pluginDropMode = false
                        if (root.shellRoot) {
                            root.shellRoot.globalFileDropped([root.pluginSourcePath]);
                        }
                    }
                } else {
                    // Not a plugin folder → normal file drop
                    root.pluginDropMode = false
                    if (root.shellRoot) {
                        root.shellRoot.globalFileDropped([root.pluginSourcePath]);
                    }
                }
                pluginCheckProc.manifestText = ""
            }
        }

        // Fillet Izquierdo (Curva cóncava usando un borde circular invertido)
        Item {
            width: 12
            height: 12
            anchors.top: parent.top
            anchors.right: parent.left
            clip: true

            Rectangle {
                width: 48
                height: 48
                radius: 24
                color: "transparent"
                border.color: "#000000"
                border.width: 12
                x: -24
                y: -12
            }
        }

        // Fillet Derecho (Curva cóncava)
        Item {
            width: 12
            height: 12
            anchors.top: parent.top
            anchors.left: parent.right
            clip: true

            Rectangle {
                width: 48
                height: 48
                radius: 24
                color: "transparent"
                border.color: "#000000"
                border.width: 12
                x: -12
                y: -12
            }
        }

        // Contenedor para las secciones superiores (workspaces, reloj/spotify, batería/wifi/tray)
        Item {
            id: content
            width: parent.width
            height: Theme.barHeight
            anchors.top: parent.top

            LeftSection {
                id: leftSection
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
            }

            // ── Centro: Reloj (modo normal, activeWidget === 0) ──
            // La isla crece dinámicamente con el contenido; el centro siempre está centrado.
            CenterSection {
                id: centerSection
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                shellRoot: root.shellRoot
                pluginManager: root.pluginManager
                // Mostrar siempre si hay OSD; de lo contrario ocultar si la isla está expandida
                opacity: (root.shellRoot && root.shellRoot.osdType !== "") ? 1.0 : (root.isFileHovered || root.isPluginInstallExpanded || root.isLauncherExpanded || root.isNotifExpanded || root.isWallpaperExpanded || root.activeDynamicWidget !== null ? 0.0 : 1.0)
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                onClicked: (widgetObj) => {
                    if (widgetObj === "plugins") {
                        if (root.isNotifExpanded && notifCenter.currentSection === 4) {
                            root.toggleNotifExpanded();
                        } else {
                            centerSection.currentTabIndex = centerSection.centerWidgets.length + 1;
                            notifCenter.currentSection = 4;
                            if (root.shellRoot) {
                                root.shellRoot.notifOpen = true;
                                root.shellRoot.activeDynamicWidget = null;
                            }
                        }
                    } else if (widgetObj) {
                        root.toggleDynamicWidget(widgetObj)
                    } else {
                        if (root.isNotifExpanded && notifCenter.currentSection !== 4) {
                            root.toggleNotifExpanded();
                        } else {
                            centerSection.currentTabIndex = 0;
                            notifCenter.currentSection = 0;
                            if (root.shellRoot) {
                                root.shellRoot.notifOpen = true;
                                root.shellRoot.activeDynamicWidget = null;
                            }
                        }
                    }
                }
            }

            // Área de cierre cuando la isla está expandida (sobre el notch central)
            MouseArea {
                anchors.fill: centerSection
                enabled: root.isCenterExpanded
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.isNotifExpanded) root.toggleNotifExpanded();
                    if (root.activeDynamicWidget !== null) root.toggleDynamicWidget(root.activeDynamicWidget);
                }
            }

            // The clickable area was removed because CenterSection now handles clicks and swipes directly.

            // ── Dynamic Widget Icons ──
            Row {
                id: dynamicWidgetsRow
                anchors.right: rightSection.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                z: 11
                
                Repeater {
                    model: root.pluginManager ? root.pluginManager.activeWidgets : []
                    delegate: Loader {
                        sourceComponent: modelData.barIcon
                        property var rootWidget: root
                        property var shellRoot: root.shellRoot
                    }
                }
            }

            RightSection {
                id: rightSection
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                onTrayMenuRequested: (trayItem, gx, gy) => root.trayMenuRequested(trayItem, gx, gy)
            }

        }
    }
}
