// optional/screenrec/Main.qml — Screen Record Plugin
// Type: widget — expone barIcon + expandedPanel
import QtQuick
import Quickshell
import "../../style"

Item {
    id: widget

    // Identificador único (debe coincidir con plugin.json)
    property string pluginId: "com.luisp.screenrec"

    // Inyectados por Bar.qml
    property var shellRoot: null
    property var rootWidget: null

    // Indica si la pestaña de este plugin está activa en el CenterSection
    property bool isCenterTabActive: false

    // Icono personalizado para la pestaña global
    property string tabIcon: "󰑋"

    readonly property int expandedWidth: 500
    readonly property int expandedHeight: 250

    // ── Local Settings ────────────────────────────────────────────────────
    property bool hideBarIcon: false
    property string fps: "60"
    property bool recordAudio: false
    property string audioDevice: "default"
    property string encodeResolution: "default"

    property var settingsConfig: [
        { id: "hideBarIcon", name: "Hide Bar Icon", type: "bool", defaultValue: false },
        { id: "fps", name: "FPS", type: "options", options: ["30", "60"], defaultValue: "60" },
        { id: "recordAudio", name: "Record Audio", type: "bool", defaultValue: false },
        { id: "audioDevice", name: "Audio Device (e.g. default)", type: "string", defaultValue: "default" },
        { id: "encodeResolution", name: "Encode Resolution (e.g. 1920x1080)", type: "string", defaultValue: "default" }
    ]

    Component.onCompleted: {
        if (parent && parent.getSetting) {
            hideBarIcon = parent.getSetting(pluginId, "hideBarIcon", false);
            fps = parent.getSetting(pluginId, "fps", "60");
            recordAudio = parent.getSetting(pluginId, "recordAudio", false);
            audioDevice = parent.getSetting(pluginId, "audioDevice", "default");
            encodeResolution = parent.getSetting(pluginId, "encodeResolution", "default");
        }
    }

    Connections {
        target: widget.parent && widget.parent.settingChanged ? widget.parent : null
        function onSettingChanged(id, key, value) {
            if (id === widget.pluginId) {
                if (key === "hideBarIcon") widget.hideBarIcon = value;
                else if (key === "fps") widget.fps = value;
                else if (key === "recordAudio") widget.recordAudio = value;
                else if (key === "audioDevice") widget.audioDevice = value;
                else if (key === "encodeResolution") widget.encodeResolution = value;
            }
        }
    }

    // ── barIcon ───────────────────────────────────────────────────────────
    property Component barIcon: Component {
        Item {
            implicitWidth: 24
            implicitHeight: 24

            width: (widget.isCenterTabActive || widget.hideBarIcon) ? 0 : implicitWidth
            opacity: (widget.isCenterTabActive || widget.hideBarIcon) ? 0.0 : 1.0
            visible: opacity > 0
            clip: true

            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

            Component.onCompleted: {
                if (shellRoot && widget.shellRoot !== shellRoot) widget.shellRoot = shellRoot
                if (rootWidget && widget.rootWidget !== rootWidget) widget.rootWidget = rootWidget
            }

            Text {
                anchors.centerIn: parent
                text: "󰑋"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: 18
                color: {
                    if (widget.shellRoot && widget.shellRoot.screenRecState === "recording") return Theme.danger
                    if (widget.shellRoot && widget.shellRoot.screenRecState === "paused") return Theme.warning
                    return Theme.textMuted
                }

                SequentialAnimation on opacity {
                    running: widget.shellRoot && widget.shellRoot.screenRecState === "recording"
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.3; duration: 800 }
                    NumberAnimation { from: 0.3; to: 1.0; duration: 800 }
                }
                Behavior on color { ColorAnimation { duration: 150 } }
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
                    text: "󰑋"
                    font.family: "Iosevka Nerd Font"
                    font.pixelSize: 14
                    color: {
                        if (widget.shellRoot && widget.shellRoot.screenRecState === "recording") return Theme.danger
                        if (widget.shellRoot && widget.shellRoot.screenRecState === "paused") return Theme.warning
                        return Theme.textMuted
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (widget.shellRoot && widget.shellRoot.screenRecState === "recording") return "Recording"
                        if (widget.shellRoot && widget.shellRoot.screenRecState === "paused") return "Paused"
                        return "Screen Recorder"
                    }
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }
            }
        }
    }

    // ── expandedPanel ─────────────────────────────────────────────────────
    property Component expandedPanel: Component {
        Item {
            id: panelRoot

            // Bar.qml's Loader.onLoaded already pushes shellRoot into widget before
            // this component is shown, so widget.shellRoot is guaranteed non-null here.
            // We also capture it into a local property for a stable binding.
            property var _shell: widget.shellRoot

            // Keep _shell in sync if shellRoot ever changes (e.g. after hot-reload)
            Connections {
                target: widget
                function onShellRootChanged() { panelRoot._shell = widget.shellRoot; }
            }

            ScreenRecContent {
                anchors.fill: parent
                rootWidget: panelRoot._shell
                pluginWidget: widget
            }
        }
    }
}
