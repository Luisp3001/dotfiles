// optional/spotify/Main.qml — Spotify Widget Plugin
// Type: widget — expone barIcon + expandedPanel para la Dynamic Island
// Muestra estado de Spotify en el icono de la barra y el reproductor completo en el panel expandido.
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../style"

Item {
    id: widget

    // Identificador único (debe coincidir con plugin.json)
    property string pluginId: "com.luisp.spotify"

    // shellRoot y rootWidget — inyectados por Bar.qml cuando carga barIcon/expandedPanel
    property var shellRoot: null
    property var rootWidget: null
    
    // Indica si la pestaña de este plugin está activa en el CenterSection
    property bool isCenterTabActive: false

    // Icono personalizado para la pestaña global
    property string tabIcon: "󰓇"

    // ── Settings ──────────────────────────────────────────────────────────
    property bool showInIsland: true
    property bool showCava: true
    property bool showLyrics: true
    property bool showBeatAnimation: true
    property bool useGifInsteadOfVinyl: false

    property var settingsConfig: [
        { id: "showInIsland", name: "Mostrar icono en barra superior", type: "bool", defaultValue: true },
        { id: "showCava", name: "Activar módulo CAVA", type: "bool", defaultValue: true },
        { id: "showLyrics", name: "Mostrar letras de canciones", type: "bool", defaultValue: true },
        { id: "showBeatAnimation", name: "Animación de vinilo al ritmo", type: "bool", defaultValue: true },
        { id: "useGifInsteadOfVinyl", name: "Reemplazar vinilo por GIF animado", type: "bool", defaultValue: false }
    ]

    Component.onCompleted: {
        if (parent && parent.getSetting) {
            showInIsland = parent.getSetting(pluginId, "showInIsland", true)
            showCava = parent.getSetting(pluginId, "showCava", true)
            showLyrics = parent.getSetting(pluginId, "showLyrics", true)
            showBeatAnimation = parent.getSetting(pluginId, "showBeatAnimation", true)
            useGifInsteadOfVinyl = parent.getSetting(pluginId, "useGifInsteadOfVinyl", false)
        }
    }

    Connections {
        target: widget.parent && widget.parent.settingChanged ? widget.parent : null
        function onSettingChanged(id, key, value) {
            if (id === widget.pluginId) {
                if (key === "showInIsland") widget.showInIsland = value
                if (key === "showCava") widget.showCava = value
                if (key === "showLyrics") widget.showLyrics = value
                if (key === "showBeatAnimation") widget.showBeatAnimation = value
                if (key === "useGifInsteadOfVinyl") widget.useGifInsteadOfVinyl = value
            }
        }
    }

    // ── Detección de Spotify vía MPRIS ──────────────────────────────────────
    property var _allPlayers: Mpris.players.values
    property var spotifyPlayer: {
        for (var i = 0; i < _allPlayers.length; i++) {
            var p = _allPlayers[i];
            if (p.identity && p.identity.toLowerCase().includes("spotify"))
                return p;
        }
        return null;
    }
    property bool hasSpotify: spotifyPlayer !== null
    property bool isPlaying: hasSpotify && spotifyPlayer.playbackState === MprisPlaybackState.Playing

    // Dimensiones del panel expandido
    readonly property int expandedWidth: 600
    readonly property int expandedHeight: 280

    // ── barIcon ───────────────────────────────────────────────────────────
    // Componente que se inserta en la fila de íconos de la Dynamic Island
    property Component barIcon: Component {
        Item {
            implicitWidth: spotifyIconRow.implicitWidth + 8
            implicitHeight: 24
            
            width: (!widget.showInIsland || widget.isCenterTabActive) ? 0 : implicitWidth
            opacity: (!widget.showInIsland || widget.isCenterTabActive) ? 0.0 : 1.0
            visible: opacity > 0
            clip: true
            
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
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
                id: spotifyIconRow
                anchors.centerIn: parent
                spacing: 6

                // Ícono de Spotify
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F1BC}"
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    color: widget.isPlaying ? Theme.accent : Theme.textMuted
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

            SpotifyWidget {
                anchors.fill: parent
                showCava: widget.showCava
                showLyrics: widget.showLyrics
                showBeatAnimation: widget.showBeatAnimation
                useGifInsteadOfVinyl: widget.useGifInsteadOfVinyl
            }
        }
    }

    // ── centerWidget ──────────────────────────────────────────────────────
    // Componente que se muestra como pestaña en el CenterSection de la isla
    property Component centerWidget: Component {
        Item {
            implicitWidth: centerRow.implicitWidth
            implicitHeight: 24

            Row {
                id: centerRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F1BC}"
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    color: widget.isPlaying ? Theme.accent : Theme.textMuted
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: widget.hasSpotify && widget.spotifyPlayer.trackTitle ? widget.spotifyPlayer.trackTitle : "Spotify"
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                    
                    // Simple truncación si es muy largo
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 200)
                }
            }
        }
    }
}
