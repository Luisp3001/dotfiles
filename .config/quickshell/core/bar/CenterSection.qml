// modules/bar/CenterSection.qml — Sección central con OSD de volumen/brillo y pestañas dinámicas
import QtQuick
import "../../components"
import "../../style"

Item {
    id: root
    implicitHeight: Theme.barHeight

    property var shellRoot: null
    property var pluginManager: null

    signal clicked(var widgetObj)

    // ── Dynamic Tabs from Plugins ─────────────────────────────────────
    property var _allPlugins: pluginManager ? pluginManager.orderedWidgets : []
    property var centerWidgets: {
        var arr = [];
        for (var i = 0; i < _allPlugins.length; i++) {
            var w = _allPlugins[i];
            if (w.centerWidget !== undefined) {
                arr.push(w);
            }
        }
        return arr;
    }

    property int currentTabIndex: 0
    
    onCurrentTabIndexChanged: updateWidgetStates()
    onCenterWidgetsChanged: {
        if (currentTabIndex > centerWidgets.length + 1) {
            currentTabIndex = 0;
        }
        updateWidgetStates();
    }
    
    function updateWidgetStates() {
        for (var i = 0; i < centerWidgets.length; i++) {
            var w = centerWidgets[i];
            if (w.isCenterTabActive !== undefined) {
                w.isCenterTabActive = (currentTabIndex === i + 1);
            }
        }
    }

    // ── Dynamic Width ─────────────────────────────────────────────────
    property int activeTabWidth: {
        if (currentTabIndex === 0) return clock.implicitWidth + 20;
        if (currentTabIndex === centerWidgets.length + 1) return pluginsCenterTab.implicitWidth + 20;
        var activeLoader = null;
        for (var i = 0; i < tabsRepeater.count; i++) {
            if (i + 1 === currentTabIndex) {
                activeLoader = tabsRepeater.itemAt(i);
                break;
            }
        }
        if (activeLoader && activeLoader.item) {
            return activeLoader.item.implicitWidth + 20;
        }
        return clock.implicitWidth + 20;
    }

    implicitWidth: Math.max(activeTabWidth, osdRow.implicitWidth + 24)
    Behavior on implicitWidth { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

    // ── OSD state from shell ──────────────────────────────────────────
    readonly property bool osdActive: shellRoot && shellRoot.osdType !== ""
    readonly property string osdType: shellRoot ? shellRoot.osdType : ""
    readonly property int osdValue: shellRoot ? shellRoot.osdValue : 0
    readonly property string osdIcon: shellRoot ? shellRoot.osdIcon : ""

    // ── Tabs Container ────────────────────────────────────────────────
    Item {
        id: tabsContainer
        anchors.fill: parent
        opacity: root.osdActive ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        // Clock (Tab 0)
        Clock {
            id: clock
            anchors.centerIn: parent
            opacity: root.currentTabIndex === 0 ? 1.0 : 0.0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }

        // Plugins Manager (Tab 1)
        Item {
            id: pluginsCenterTab
            anchors.centerIn: parent
            opacity: root.currentTabIndex === root.centerWidgets.length + 1 ? 1.0 : 0.0
            visible: opacity > 0
            implicitWidth: pluginsCenterRow.implicitWidth
            implicitHeight: 24
            Behavior on opacity { NumberAnimation { duration: 220 } }

            Row {
                id: pluginsCenterRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰏗"
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    color: Theme.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Plugins activos: " + (root.shellRoot && root.shellRoot.pluginManager ? root.shellRoot.pluginManager.activePluginsCount : 0)
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.textPrimary
                }
            }
            
            Component.onCompleted: root.activeTabWidth = root.activeTabWidth
        }

        // Plugin Tabs (Tab 2..N)
        Repeater {
            id: tabsRepeater
            model: root.centerWidgets
            delegate: Loader {
                anchors.centerIn: parent
                sourceComponent: modelData.centerWidget
                property var widgetPlugin: modelData
                property var shellRoot: root.shellRoot

                opacity: root.currentTabIndex === index + 1 ? 1.0 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                
                // Force activeTabWidth to re-evaluate when item finishes loading
                onLoaded: root.activeTabWidth = root.activeTabWidth 
            }
        }
    }

    // ── OSD Overlay (visible when volume/brightness changes) ──────────
    Row {
        id: osdRow
        anchors.centerIn: parent
        spacing: 6
        opacity: root.osdActive ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        // Icon
        Text {
            id: osdIconText
            text: root.osdIcon
            color: Theme.accent
            font.family: Theme.fontMono
            font.pixelSize: 13
            anchors.verticalCenter: parent.verticalCenter
        }

        // Progress bar
        Rectangle {
            id: osdBarBg
            width: 64; height: 5; radius: 3
            color: Qt.rgba(1, 1, 1, 0.12)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: osdBarFill
                height: parent.height
                radius: parent.radius
                width: Math.max(2, parent.width * (root.osdValue / 100))
                color: root.osdType === "brightness"
                    ? Theme.warning
                    : Theme.accent
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }

        // Percentage
        Text {
            id: osdPercent
            text: root.osdValue + "%"
            color: Theme.textPrimary
            font.family: Theme.fontMono
            font.pixelSize: 10
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ── Interaction: Click and Swipe ──────────────────────────────────
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        
        property real startX: 0
        property bool dragging: false

        onPressed: (mouse) => {
            startX = mouse.x;
            dragging = false;
        }

        onPositionChanged: (mouse) => {
            if (Math.abs(mouse.x - startX) > 15) {
                dragging = true;
            }
        }

        onReleased: (mouse) => {
            if (dragging) {
                var dx = mouse.x - startX;
                if (dx > 30) {
                    // Swipe right -> previous tab
                    root.currentTabIndex = Math.max(0, root.currentTabIndex - 1);
                } else if (dx < -30) {
                    // Swipe left -> next tab
                    root.currentTabIndex = Math.min(root.centerWidgets.length + 1, root.currentTabIndex + 1);
                }
            } else {
                // Click
                if (root.currentTabIndex === 0) {
                    root.clicked(null);
                } else if (root.currentTabIndex === root.centerWidgets.length + 1) {
                    root.clicked("plugins");
                } else {
                    root.clicked(root.centerWidgets[root.currentTabIndex - 1]);
                }
            }
        }

        onWheel: (wheel) => {
            // Un poco de "debounce" o requerir cierto umbral para no volvernos locos con el scroll rápido
            if (Math.abs(wheel.angleDelta.x) > 20 || Math.abs(wheel.angleDelta.y) > 20) {
                if (wheel.angleDelta.x > 0 || wheel.angleDelta.y > 0) {
                    // Scroll up / right -> prev tab
                    root.currentTabIndex = Math.max(0, root.currentTabIndex - 1);
                } else {
                    // Scroll down / left -> next tab
                    root.currentTabIndex = Math.min(root.centerWidgets.length + 1, root.currentTabIndex + 1);
                }
            }
        }
    }
}
