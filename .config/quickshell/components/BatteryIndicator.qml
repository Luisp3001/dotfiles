// components/BatteryIndicator.qml — Nivel e ícono de batería via UPower DBus
import Quickshell
import QtQuick
import Quickshell.Io
import "../style"

Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    // Lee el nivel de batería via UPower a través de archivo del sysfs
    // Más simple y sin dependencia de DBus complejo
    FileView {
        id: capacityFile
        path: "/sys/class/power_supply/BAT0/capacity"
        onLoaded: root.updateBattery()
    }

    FileView {
        id: statusFile
        path: "/sys/class/power_supply/BAT0/status"
        onLoaded: root.updateBattery()
    }

    Timer {
        interval: 30000   // Actualiza cada 30s
        running: true
        repeat: true
        onTriggered: {
            capacityFile.reload();
            statusFile.reload();
        }
    }

    property int batteryLevel: 0
    property bool isCharging: false
    property string batteryIcon: "󰂑"   // Nerd Font: battery icons
    property color batteryColor: Theme.textPrimary

    function updateBattery() {
        const level = parseInt(capacityFile.text().trim()) || 0;
        const status = statusFile.text().trim();

        batteryLevel = level;
        isCharging = (status === "Charging" || status === "Full");

        // Ícono según nivel (Nerd Font battery icons)
        if (isCharging) {
            batteryIcon = level >= 90 ? "󰂅" : level >= 50 ? "󰂈" : "󰂆";
            batteryColor = Theme.success;
        } else if (level <= 10) {
            batteryIcon = "󰂃";
            batteryColor = Theme.danger;
        } else if (level <= 30) {
            batteryIcon = "󰁼";
            batteryColor = Theme.warning;
        } else if (level <= 60) {
            batteryIcon = "󰁿";
            batteryColor = Theme.textPrimary;
        } else if (level <= 80) {
            batteryIcon = "󰂁";
            batteryColor = Theme.textPrimary;
        } else {
            batteryIcon = "󰁹";
            batteryColor = Theme.success;
        }
    }

    Component.onCompleted: updateBattery()

    Row {
        id: row
        spacing: 4
        anchors.centerIn: parent

        Text {
            text: root.batteryIcon
            color: root.batteryColor
            font.family: Theme.fontMono
            font.pixelSize: Theme.iconSize
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.batteryLevel + "%"
            color: root.batteryColor
            font.family: Theme.fontSans
            font.pixelSize: Theme.fontSizeSm
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
