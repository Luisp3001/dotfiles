// components/Clock.qml — Reloj en tiempo real
import Quickshell
import QtQuick

import "../style"

Item {
    id: root

    implicitWidth: timeLabel.implicitWidth
    implicitHeight: timeLabel.implicitHeight

    // Actualiza cada segundo
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        id: timeLabel
        text: Qt.formatDateTime(clock.date, "HH:mm")
        color: Theme.textPrimary
        font.family: Theme.fontMono
        font.pixelSize: Theme.fontSizeMd
        font.bold: true
        anchors.centerIn: parent
    }
}
