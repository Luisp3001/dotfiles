import QtQuick
import QtQuick.Layouts
import "../../style"
import "../../components" as Lib

Rectangle {
    id: root
    property int nId: 0
    property string app: "SYSTEM"
    property string summary: "Notification"
    property string body: ""
    property string image: ""
    property string time: ""
    readonly property color cBg:      Theme.bgPill
    readonly property color cBgHover: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
    readonly property color cSheen:   Qt.rgba(1, 1, 1, 0.06)
    readonly property color cRipple:  Qt.rgba(1, 1, 1, 0.12)
    readonly property color cIconBg:  Theme.bgBar
    readonly property color cAccent:  Theme.accent
    readonly property color cFgMuted: Theme.textMuted
    readonly property color cFgMain:  Theme.textPrimary

    signal clicked()
    signal closed()

    radius: 14
    color: hovered ? cBgHover : cBg
    antialiasing: true
    border.width: 0
    clip: true

    property bool hovered: false


    // tiny highlight
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: cSheen
        opacity: hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    // ripple
    Lib.Ripple {
        id: ripple
        rippleColor: cRipple
    }

    implicitHeight: Math.max(48, mainLayout.implicitHeight + 16)

    RowLayout {
        id: mainLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 8
        spacing: 8

        Rectangle {
            width: 24
            height: 24
            radius: 999
            color: cIconBg
            Layout.alignment: Qt.AlignVCenter
            clip: true

            Image {
                anchors.fill: parent
                source: root.image
                visible: root.image !== ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(24, 24)
                asynchronous: true
            }

            Text {
                anchors.centerIn: parent
                text: "\u{F0292}" // bell outline
                visible: root.image === ""
                font.family: Theme.fontMono
                font.pixelSize: 15
                font.weight: 800
                color: cAccent
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            clip: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                
                Text {
                    text: String(root.app).toUpperCase().replace(/\n/g, ' ')
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: 700
                    color: cFgMuted
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                }
                
                Text {
                    text: root.time
                    visible: root.time !== ""
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.fontSizeXs
                    font.weight: 700
                    color: cFgMuted
                }
            }

            Text {
                text: root.summary.replace(/\n/g, ' ')
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontSizeSm
                font.weight: 700
                color: cFgMain
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.fillWidth: true
            }

            Text {
                text: root.body.replace(/\n/g, ' ')
                visible: root.body !== ""
                font.family: Theme.fontSans
                font.pixelSize: Theme.fontSizeXs
                font.weight: 300
                color: cFgMuted
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }

    property bool pressed: false

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: root.hovered = true
        onExited: root.hovered = false

        onPressed: { root.pressed = true; ripple.burst(mouse.x, mouse.y) }
        onReleased: root.pressed = false

        onClicked: root.clicked()
    }

    // Close Button Overlay
    Rectangle {
        id: closeBtn
        width: 24; height: 24; radius: 12
        color: closeBtnMa.containsMouse ? Qt.rgba(1, 0, 0, 0.2) : "transparent"
        visible: root.hovered
        z: 10
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 10

        Text {
            anchors.centerIn: parent
            text: "✕"
            color: closeBtnMa.containsMouse ? Theme.danger : Theme.textMuted
            font.pixelSize: 12
        }

        MouseArea {
            id: closeBtnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            propagateComposedEvents: false
            onClicked: (mouse) => {
                mouse.accepted = true;
                root.closed();
            }
        }
    }
}