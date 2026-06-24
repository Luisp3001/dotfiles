// optional/spotify/SpotifyWidget.qml — Reproductor de Spotify simplificado
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import Caelestia.Services
import "../../style"

Item {
    id: root
    
    property bool showCava: true
    property bool showLyrics: true
    property bool showBeatAnimation: true
    property bool useGifInsteadOfVinyl: false

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

    // ── Tracking de posición ────────────────────────────────────────────────
    property real trackPosition: hasSpotify ? spotifyPlayer.position : 0
    property real trackLength: hasSpotify ? spotifyPlayer.length : 0

    // ── Letras de Canciones (Caelestia) ─────────────────────────────────────
    property string currentTitle: hasSpotify ? spotifyPlayer.trackTitle : ""
    onCurrentTitleChanged: {
        if (hasSpotify && currentTitle !== "") {
            Lyrics.setTrack(spotifyPlayer.trackArtist, currentTitle, spotifyPlayer.trackAlbum, spotifyPlayer.length);
        } else {
            Lyrics.clearTrack();
        }
    }
    
    property int currentLyricIndex: hasSpotify ? Lyrics.indexForTime(trackPosition) : -1
    property string currentLyricText: (currentLyricIndex >= 0 && Lyrics.lyrics && currentLyricIndex < Lyrics.lyrics.length) ? Lyrics.lyrics[currentLyricIndex] : ""

    CavaProvider {
        id: cava
        bars: 36
    }

    BeatTracker {
        id: beatTracker
        onBeat: function(bpm) {
            if (root.isPlaying && root.showBeatAnimation) {
                beatAnimation.restart()
            }
        }
    }

    Loader {
        active: root.visible
        sourceComponent: Component {
            Item {
                ServiceRef { service: cava }
                ServiceRef { service: beatTracker }
            }
        }
    }

    Timer {
        interval: 1000
        running: root.isPlaying
        repeat: true
        onTriggered: root.trackPosition = root.spotifyPlayer.position
    }

    function formatTime(seconds) {
        var s = Math.floor(seconds);
        var m = Math.floor(s / 60);
        s = s % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // ── Layout principal ────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        // ── Disco de vinilo + Info ──────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 16

            // Vinilo giratorio
            Item {
                id: vinylContainer
                width: 130
                height: 130
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: (root.visible && root.showCava) ? cava.bars : 0
                    Rectangle {
                        property real val: Math.max(0.01, Math.min(1.0, cava.values ? (cava.values[index] || 0) : 0))
                        
                        width: 4
                        height: 4 + val * 24
                        radius: 2
                        color: Theme.accent
                        
                        x: vinylContainer.width / 2 - width / 2
                        y: vinylContainer.height / 2 - 50 - height - 6
                        
                        transform: Rotation {
                            origin.x: width / 2
                            origin.y: 50 + height + 6
                            angle: index * (360 / cava.bars)
                        }
                    }
                }

                Item {
                    id: vinylDisc
                    width: 100
                    height: 100
                    anchors.centerIn: parent

                    PropertyAnimation {
                        id: beatAnimation
                        target: vinylDisc
                        property: "scale"
                        from: 1.15
                        to: 1.0
                        duration: 150
                        easing.type: Easing.OutQuad
                    }

                    // Máscara circular
                    Rectangle {
                        id: discMask
                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                        layer.enabled: true
                    }

                    Image {
                        id: albumArt
                        anchors.fill: parent
                        source: root.hasSpotify ? root.spotifyPlayer.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        visible: false
                    }

                    AnimatedImage {
                        id: animImg
                        anchors.centerIn: parent
                        source: Qt.resolvedUrl("assets/kurukuru.gif")
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                        playing: root.isPlaying
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: root.useGifInsteadOfVinyl ? animImg : albumArt
                        maskEnabled: true
                        antialiasing: true
                        maskSource: discMask
                    }
                }

                // Borde sutil del vinilo
                Rectangle {
                    anchors.centerIn: parent
                    width: 100
                    height: 100
                    radius: width / 2
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: 1
                    opacity: root.isPlaying ? 0.3 : 0.1
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                }

                // Glow suave cuando reproduciendo
                Rectangle {
                    z: -1
                    anchors.centerIn: parent
                    width: 112
                    height: 112
                    radius: width / 2
                    color: Theme.accent
                    opacity: root.isPlaying ? 0.12 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 500 } }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blurMax: 24
                        blur: 1.0
                    }
                }

                // Fallback cuando no hay art
                Text {
                    anchors.centerIn: parent
                    text: "♪"
                    color: Theme.textMuted
                    font.pixelSize: 24
                    opacity: (!root.useGifInsteadOfVinyl && albumArt.status !== Image.Ready) ? 0.5 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            // Info de la canción
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: root.showLyrics ? 140 : parent.width - vinylContainer.width - parent.spacing
                spacing: 4

                Text {
                    width: parent.width
                    text: root.hasSpotify ? (root.spotifyPlayer.trackTitle || "Unknown") : "Sin reproducción"
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.hasSpotify ? (root.spotifyPlayer.trackArtist || "Unknown") : "Abre Spotify para empezar"
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontSizeSm
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.hasSpotify ? (root.spotifyPlayer.trackAlbum || "") : ""
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontSizeXs
                    opacity: 0.6
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }

            // Letra de la canción (Karaoke scroll)
            Item {
                id: lyricsContainer
                width: parent.width - vinylContainer.width - 140 - (parent.spacing * 2)
                height: 130
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                visible: root.showLyrics

                // Variable explícita para la lista (Soluciona el fallo de C++ QStringList a QML)
                property var currentLyricsList: Lyrics.lyrics

                // ── Fallback ──────────────────────────────
                Text {
                    anchors.centerIn: parent
                    text: Lyrics.loading ? "Buscando letra..." : (lyricsContainer.currentLyricsList.length === 0 ? "♪" : "")
                    color: Theme.textMuted
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.italic: true
                    visible: text !== ""
                    opacity: 0.6
                }

                // ── Scrolling lyrics ListView ───────────────────────────────
                ListView {
                    id: lyricsView
                    anchors.fill: parent
                    anchors.margins: 4

                    model: lyricsContainer.currentLyricsList
                    interactive: false // Auto-scroll
                    spacing: 8
                    
                    opacity: (!Lyrics.loading && lyricsContainer.currentLyricsList.length > 0) ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    highlightRangeMode: ListView.ApplyRange
                    preferredHighlightBegin: height / 2 - 15
                    preferredHighlightEnd: height / 2 + 15

                    Component.onCompleted: {
                        currentIndex = Qt.binding(function() {
                            return root.currentLyricIndex;
                        });
                        positionViewAtIndex(Math.max(0, currentIndex), ListView.Center);
                    }
                    onModelChanged: Qt.callLater(function() {
                        positionViewAtIndex(Math.max(0, currentIndex), ListView.Center);
                    })

                    delegate: Text {
                        id: lyricDelegate
                        required property string modelData
                        required property int index

                        width: lyricsView.width
                        text: modelData || "· · ·"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        
                        font.family: Theme.fontSans
                        font.pixelSize: ListView.isCurrentItem ? 14 : 13
                        font.weight: ListView.isCurrentItem ? Font.DemiBold : Font.Medium
                        font.italic: !ListView.isCurrentItem

                        color: ListView.isCurrentItem ? Theme.textPrimary : Theme.textMuted
                        
                        scale: ListView.isCurrentItem ? 1.05 : 1.0
                        opacity: ListView.isCurrentItem ? 1.0 : 0.45

                        // Animaciones suaves
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 250 } }
                        Behavior on opacity { NumberAnimation { duration: 250 } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.hasSpotify) {
                                    var seekTime = Lyrics.timeForIndex(lyricDelegate.index);
                                    root.spotifyPlayer.position = seekTime;
                                    root.trackPosition = seekTime;
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            width: 1
            height: 12
        }

        // ── Barra de progreso ───────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 4


            // Track bar
            Item {
                width: parent.width
                height: 5

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                Rectangle {
                    id: progressFill
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    radius: height / 2
                    color: Theme.accent
                    property real ratio: root.trackLength > 0
                        ? Math.min(1.0, root.trackPosition / root.trackLength) : 0

                    width: Math.max(radius * 2, parent.width * ratio)

                    Behavior on width {
                        NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                    }

                    // Dot al final
                    Rectangle {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: -3
                        }
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.accent
                        visible: progressFill.ratio > 0.01

                        Rectangle {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            radius: 7
                            color: "transparent"
                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                            border.width: 1.5
                        }
                    }
                }

                // Click para seek
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: function(mouse) {
                        if (!root.hasSpotify || root.trackLength <= 0) return;
                        var ratio = Math.max(0, Math.min(1, mouse.x / parent.width));
                        root.spotifyPlayer.position = ratio * root.trackLength;
                        root.trackPosition = ratio * root.trackLength;
                    }
                }
            }

            // Timestamps
            Row {
                width: parent.width

                Text {
                    id: posText
                    text: root.formatTime(root.trackPosition)
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                }

                Item { width: parent.width - posText.width - durText.width; height: 1 }

                Text {
                    id: durText
                    text: root.trackLength > 0 ? root.formatTime(root.trackLength) : "--:--"
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 9
                }
            }
        }

        // ── Controles de reproducción ───────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16

            ControlButton {
                icon: "󰒮"
                onClicked: { if (root.hasSpotify) root.spotifyPlayer.previous() }
            }

            ControlButton {
                icon: root.isPlaying ? "󰏤" : "󰐊"
                highlighted: true
                onClicked: {
                    if (!root.hasSpotify) return;
                    if (root.isPlaying)
                        root.spotifyPlayer.pause();
                    else
                        root.spotifyPlayer.play();
                }
            }

            ControlButton {
                icon: "󰒭"
                onClicked: { if (root.hasSpotify) root.spotifyPlayer.next() }
            }
        }
    }
}
