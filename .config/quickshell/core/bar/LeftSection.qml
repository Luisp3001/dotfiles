// modules/bar/LeftSection.qml — Sección izquierda: workspaces
import QtQuick
import "../../components"
import "../../style"
import "../workspaces"

Row {
    id: root
    spacing: Theme.spacing + 2

    WorkspaceIndicator {
        anchors.verticalCenter: parent.verticalCenter
    }
}
