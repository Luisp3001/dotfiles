import QtQuick
import QtQuick.Layouts
import "../../style"

Item {
    id: notifContent
    property var rootWidget
    property alias notifColumn: notifColumn
    implicitHeight: notifColumn.implicitHeight

    ColumnLayout {
        id: notifColumn
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // App icon / notification icon
            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                Layout.alignment: Qt.AlignVCenter
                radius: 5
                color: "#2a2d3a"

                Image {
                    id: notifImage
                    anchors.fill: parent
                    anchors.margins: 2
                    source: rootWidget.notifHandler.image || ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    cache: false
                    visible: status === Image.Ready
                }

                // Fallback icon
                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.pixelSize: 20
                    visible: notifImage.status !== Image.Ready
                    opacity: 0.7
                }

                // Rounded overlay
                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: "transparent"
                    border.color: "#3d4150"
                    border.width: 1
                }
            }

            // Text content
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                clip: true

                // App name
                Text {
                    text: rootWidget.notifHandler.appName
                    color: Theme.textMuted
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                    font.weight: Font.Normal
                    opacity: 0.8
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                    visible: text !== ""
                }

                // Summary (title)
                Text {
                    text: rootWidget.notifHandler.summary
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.fillWidth: true
                }

                // Body
                Text {
                    text: rootWidget.notifHandler.body
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    font.weight: Font.Normal
                    opacity: 0.7
                    elide: Text.ElideRight
                    maximumLineCount: 3
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    visible: text !== ""
                }
            }

            // Urgency indicator dot
            Rectangle {
                id: urgencyDot
                Layout.preferredWidth: 8
                Layout.preferredHeight: 8
                Layout.alignment: Qt.AlignVCenter
                radius: 4
                visible: rootWidget.notifHandler.urgency === 2
                color: Theme.accent

                SequentialAnimation on opacity {
                    running: urgencyDot.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                }
            }
        }

        // Action buttons 
        RowLayout {
            id: actionsRow
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 8
            visible: actionRepeater.count > 0

            Repeater {
                id: actionRepeater
                model: rootWidget.notifHandler.actions
                
                delegate: Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    radius: 8
                    color: actionMouse.containsMouse ? Theme.accent : "transparent"
                    border.color: actionMouse.containsMouse ? "transparent" : Theme.accentDim
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.text || modelData.identifier || ""
                        color: actionMouse.containsMouse ? Theme.bgMain : Theme.textPrimary
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.invoke) modelData.invoke();
                            rootWidget.notifHandler.dismiss();
                        }
                    }
                }
            }
        }
    }
}
