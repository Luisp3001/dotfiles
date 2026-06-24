// modules/bar/ControlButton.qml — Botón circular para controles de reproducción
import QtQuick
import "../../style"

Rectangle {
    id: root

    property string icon: ""
    property bool highlighted: false

    signal clicked()

    width: 32
    height: 32
    radius: 16

    color: {
        if (mouseArea.pressed) return highlighted ? Theme.accent : Qt.rgba(1, 1, 1, 0.15);
        if (mouseArea.containsMouse) return highlighted ? Qt.darker(Theme.accent, 1.2) : Qt.rgba(1, 1, 1, 0.1);
        return highlighted ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85) : "transparent";
    }

    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        color: {
            if (mouseArea.pressed && root.highlighted) return "#0d0d0d";
            return Theme.textPrimary;
        }
        font.family: Theme.fontMono
        font.pixelSize: 14

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
