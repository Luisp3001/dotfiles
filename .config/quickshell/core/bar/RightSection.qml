// modules/bar/RightSection.qml — Sección derecha: batería, wifi, divisor y tray
import QtQuick
import "../../components"
import "../../style"
import "../systemtray"

Row {
    id: root
    spacing: Theme.spacing + 2

    // Reenviamos la señal del SystemTray hacia arriba (Bar → shell.qml)
    signal trayMenuRequested(var trayItem, real globalX, real globalY)

    BatteryIndicator {
        anchors.verticalCenter: parent.verticalCenter
    }

    WifiIndicator {
        anchors.verticalCenter: parent.verticalCenter
    }

    // Separador visual
    Rectangle {
        width: 1
        height: 16
        color: Theme.accentDim
        opacity: 0.4
        anchors.verticalCenter: parent.verticalCenter
    }

    SystemTray {
        anchors.verticalCenter: parent.verticalCenter
        onMenuRequested: (trayItem, gx, gy) => root.trayMenuRequested(trayItem, gx, gy)
    }
}
