// components/SystemTray.qml — Bandeja del sistema (íconos de aplicaciones)
import Quickshell
import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Quickshell.DBusMenu
import "../../style"

Item {
    id: root

    implicitWidth: trayRow.implicitWidth
    implicitHeight: trayRow.implicitHeight

    // Señal emitida cuando el usuario hace clic derecho en un ícono con menú
    // El padre (shell.qml) escucha esto y abre el PopupWindow con los datos correctos
    signal menuRequested(var trayItem, real globalX, real globalY)

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: Theme.spacing

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayDelegate
                required property var modelData

                width: Theme.iconSize + 8
                height: Theme.iconSize + 8

                Image {
                    anchors.centerIn: parent
                    width: Theme.iconSize + 5
                    height: Theme.iconSize + 5
                    source: modelData.icon
                    smooth: true
                    mipmap: true

                    opacity: trayItemArea.containsMouse ? 0.7 : 1.0
                    Behavior on opacity {
                        NumberAnimation { duration: 120 }
                    }
                }

                MouseArea {
                    id: trayItemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            modelData.activate();
                        } else if (mouse.button === Qt.RightButton) {
                            if (modelData.hasMenu) {
                                // Calculamos coordenadas globales del ícono
                                var pt = trayDelegate.mapToItem(null, 0, trayDelegate.height);
                                root.menuRequested(modelData, pt.x, pt.y);
                            } else {
                                modelData.secondaryActivate();
                            }
                        }
                    }
                }
            }
        }
    }
}
