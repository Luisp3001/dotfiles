// plugins/dock/Main.qml — Plugin entry point
// Loaded dynamically by PluginManager. Creates per-screen PanelWindows.
// The Dock visual component is loaded inside each PanelWindow.
import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
    id: pluginRoot
    visible: false

    Variants {
        model: Quickshell.screens

        QtObject {
            required property var modelData

            property var dockWindow: PanelWindow {
                screen: modelData
                anchors { bottom: true; left: true; right: true }
                implicitHeight: 120
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "quickshell-dock"

                mask: Region { item: dockWidget.inputRegion }

                Dock {
                    id: dockWidget
                    anchors.fill: parent
                }
            }
        }
    }
}
