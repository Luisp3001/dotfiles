// modules/bar/PluginsWidget.qml — UI for managing installed plugins
import QtQuick
import Quickshell
import "../../style"

Item {
    id: root
    property var shellRoot: null
    property bool showOrderView: false

    readonly property int activePluginsCount: root.shellRoot && root.shellRoot.pluginManager
        ? root.shellRoot.pluginManager.activePluginsCount
        : 0

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // Header
        Item {
            width: parent.width
            height: 30

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    text: root.showOrderView ? "󰒍" : "󰏗"
                    color: Theme.accent
                    font.family: Theme.fontMono
                    font.pixelSize: 16
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.showOrderView ? "Orden del Tab Bar" : "Plugins activos: " + root.activePluginsCount
                    color: Theme.textPrimary
                    font.family: Theme.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Toggle View Button
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 28; radius: 6
                color: viewToggleMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                border.width: 1; border.color: root.showOrderView ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)

                Text {
                    text: root.showOrderView ? "󰀦" : "󰒍"
                    color: root.showOrderView ? Theme.accent : Theme.textPrimary
                    font.family: Theme.fontMono
                    font.pixelSize: 14
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: viewToggleMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showOrderView = !root.showOrderView
                }
            }
        }

        // List of Plugins
        ListView {
            id: pluginList
            width: parent.width
            height: parent.height - 42
            clip: true
            spacing: 8
            visible: !root.showOrderView
            model: root.shellRoot && root.shellRoot.pluginManager ? root.shellRoot.pluginManager.model : null

            delegate: Rectangle {
                id: delegateRoot
                readonly property string pluginId: model.id
                property bool isSettingsOpen: false
                
                width: ListView.view.width
                height: isSettingsOpen ? 60 + settingsColumn.implicitHeight + 10 : 60
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                clip: true
                
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.04)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                Row {
                    width: parent.width
                    height: 60
                    anchors.margins: 10
                    spacing: 12

                    // Icon based on type
                    Rectangle {
                        width: 40; height: 40
                        radius: 8
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1)
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: model.type === "window" ? "󰖲" : "󰏗"
                            color: Theme.accent
                            font.family: Theme.fontMono
                            font.pixelSize: 18
                        }
                    }

                    // Info
                    Column {
                        width: parent.width - 40 - 12 - controlsRow.width - 12 // Remaining width minus icon, spacing, and dynamic controls
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: model.name || model.id
                            color: Theme.textPrimary
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: model.id
                            color: Theme.textMuted
                            font.family: Theme.fontSans
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    // Controls
                    Row {
                        id: controlsRow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        property bool confirmDelete: false

                        // Settings Button
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 6
                            color: settingsMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                            visible: root.shellRoot && root.shellRoot.pluginManager && root.shellRoot.pluginManager._activeObjects[delegateRoot.pluginId] && root.shellRoot.pluginManager._activeObjects[delegateRoot.pluginId].settingsConfig !== undefined
                            
                            Text {
                                text: "󰒓"
                                color: delegateRoot.isSettingsOpen ? Theme.accent : Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 14
                                anchors.centerIn: parent
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            
                            MouseArea {
                                id: settingsMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: delegateRoot.isSettingsOpen = !delegateRoot.isSettingsOpen
                            }
                        }

                        // Toggle switch (hidden when confirming delete)
                        Rectangle {
                            width: 36
                            height: 20
                            radius: 10
                            color: model.enabled ? Theme.success : Qt.rgba(1, 1, 1, 0.1)
                            visible: !controlsRow.confirmDelete
                            Behavior on color { ColorAnimation { duration: 200 } }

                            Rectangle {
                                width: 16; height: 16
                                radius: 8
                                color: "#11111b"
                                anchors.verticalCenter: parent.verticalCenter
                                x: model.enabled ? parent.width - width - 2 : 2
                                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.shellRoot && root.shellRoot.pluginManager) {
                                        root.shellRoot.pluginManager.setPluginEnabled(model.id, !model.enabled)
                                    }
                                }
                            }
                        }

                        // Uninstall Button
                        Rectangle {
                            width: controlsRow.confirmDelete ? 80 : 28
                            height: 28
                            radius: 6
                            color: controlsRow.confirmDelete ? Theme.danger : (trashMa.containsMouse ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.15) : "transparent")
                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            clip: true

                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: "󰆴"
                                    color: controlsRow.confirmDelete ? "#11111b" : (trashMa.containsMouse ? Theme.danger : Theme.textMuted)
                                    font.family: Theme.fontMono
                                    font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                Text {
                                    text: "Delete?"
                                    visible: controlsRow.confirmDelete
                                    color: "#11111b"
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: trashMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!controlsRow.confirmDelete) {
                                        controlsRow.confirmDelete = true;
                                        resetDeleteTimer.start();
                                    } else {
                                        if (root.shellRoot && root.shellRoot.pluginManager) {
                                            root.shellRoot.pluginManager.uninstallPlugin(model.id)
                                        }
                                    }
                                }
                            }

                            Timer {
                                id: resetDeleteTimer
                                interval: 3000
                                onTriggered: controlsRow.confirmDelete = false
                            }
                        }
                    }
                }
                
                // Settings Panel
                Column {
                    id: settingsColumn
                    width: parent.width - 24
                    x: 12
                    y: 60
                    spacing: 8
                    visible: delegateRoot.isSettingsOpen && opacity > 0
                    opacity: delegateRoot.isSettingsOpen ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    
                    Repeater {
                        model: root.shellRoot && root.shellRoot.pluginManager && root.shellRoot.pluginManager._activeObjects[delegateRoot.pluginId] ? root.shellRoot.pluginManager._activeObjects[delegateRoot.pluginId].settingsConfig : []
                        
                        Row {
                            width: parent.width
                            height: 24
                            
                            Text {
                                text: modelData.name
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - ((modelData.type === "string" || modelData.type === "options") ? 130 : 40)
                                elide: Text.ElideRight
                            }
                            
                            // Control basado en tipo
                            Loader {
                                anchors.verticalCenter: parent.verticalCenter
                                width: (modelData.type === "string" || modelData.type === "options") ? 120 : 32
                                
                                sourceComponent: {
                                    if (modelData.type === "string") return stringInputComp;
                                    if (modelData.type === "options") return optionsComp;
                                    return boolToggleComp; // default to bool
                                }
                                
                                property var modelDataRef: modelData
                                property string pluginIdRef: delegateRoot.pluginId
                                property var managerRef: root.shellRoot ? root.shellRoot.pluginManager : null
                            }
                        }
                    }
                    
                    Component {
                        id: boolToggleComp
                        Rectangle {
                            width: 32
                            height: 18
                            radius: 9
                            
                            property bool settingValue: {
                                if (managerRef) {
                                    var dummy = managerRef._pluginSettings
                                    return managerRef.getSetting(pluginIdRef, modelDataRef.id, modelDataRef.defaultValue) === true
                                }
                                return modelDataRef.defaultValue === true
                            }
                            
                            color: settingValue ? Theme.success : Qt.rgba(1, 1, 1, 0.1)
                            Behavior on color { ColorAnimation { duration: 200 } }
                            
                            Rectangle {
                                width: 14; height: 14
                                radius: 7
                                color: "#11111b"
                                anchors.verticalCenter: parent.verticalCenter
                                x: parent.settingValue ? parent.width - width - 2 : 2
                                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (managerRef) {
                                        managerRef.setSetting(pluginIdRef, modelDataRef.id, !parent.settingValue)
                                    }
                                }
                            }
                        }
                    }
                    
                    Component {
                        id: stringInputComp
                        Rectangle {
                            width: 120
                            height: 20
                            radius: 4
                            color: Qt.rgba(0, 0, 0, 0.3)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.1)
                            
                            TextInput {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                verticalAlignment: TextInput.AlignVCenter
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                selectByMouse: true
                                clip: true
                                
                                text: {
                                    if (managerRef) {
                                        var dummy = managerRef._pluginSettings
                                        return managerRef.getSetting(pluginIdRef, modelDataRef.id, modelDataRef.defaultValue)
                                    }
                                    return modelDataRef.defaultValue
                                }
                                
                                onEditingFinished: {
                                    if (managerRef) {
                                        managerRef.setSetting(pluginIdRef, modelDataRef.id, text.trim())
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: optionsComp
                        Rectangle {
                            id: optionsPill
                            width: 120
                            height: 26
                            radius: 6
                            color: optionsMa.containsMouse
                                ? Qt.rgba(1, 1, 1, 0.12)
                                : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            border.color: optionsMa.containsMouse
                                ? Qt.rgba(1, 1, 1, 0.25)
                                : Qt.rgba(1, 1, 1, 0.13)

                            Behavior on color       { ColorAnimation { duration: 130 } }
                            Behavior on border.color { ColorAnimation { duration: 130 } }

                            scale: optionsMa.pressed ? 0.96 : 1.0
                            Behavior on scale { NumberAnimation { duration: 90 } }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 6
                                spacing: 0

                                Text {
                                    id: optionValueText
                                    width: parent.width - chevron.width - 2
                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter
                                    color: Theme.textPrimary
                                    font.family: Theme.fontSans
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    text: {
                                        if (managerRef) {
                                            var dummy = managerRef._pluginSettings
                                            return managerRef.getSetting(pluginIdRef, modelDataRef.id, modelDataRef.defaultValue)
                                        }
                                        return modelDataRef.defaultValue
                                    }
                                }

                                Text {
                                    id: chevron
                                    width: 14
                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Theme.textMuted
                                    font.family: Theme.fontMono
                                    font.pixelSize: 10
                                    text: "" // nf-fa-angle_down
                                }
                            }

                            MouseArea {
                                id: optionsMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (managerRef && modelDataRef.options) {
                                        var current = managerRef.getSetting(pluginIdRef, modelDataRef.id, modelDataRef.defaultValue);
                                        var idx = modelDataRef.options.indexOf(current);
                                        var nextIdx = (idx + 1) % modelDataRef.options.length;
                                        managerRef.setSetting(pluginIdRef, modelDataRef.id, modelDataRef.options[nextIdx]);
                                    }
                                }
                            }
                        }
                    }
                    
                    Item { width: 1; height: 4 } // bottom padding
                }
            }

            // Empty state
            Item {
                width: parent.width
                height: 100
                visible: pluginList.count === 0
                anchors.centerIn: parent

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "󰏗"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 24
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "No plugins installed"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }

        // Tab Order View
        ListView {
            id: orderList
            width: parent.width
            height: parent.height - 42
            clip: true
            spacing: 0
            visible: root.showOrderView
            model: root.shellRoot && root.shellRoot.pluginManager ? root.shellRoot.pluginManager.orderedWidgets : null

            delegate: Item {
                id: orderDelegate
                width: ListView.view.width
                
                property bool hasTab: modelData.centerWidget !== undefined
                
                // Hide if it doesn't generate a tab
                height: hasTab ? 68 : 0
                visible: hasTab
                opacity: hasTab ? 1.0 : 0.0
                
                // Calculate actual valid targets for Up/Down
                property int prevVisibleIdx: {
                    if (!orderList.model) return -1;
                    var idx = index - 1;
                    while (idx >= 0 && orderList.model[idx].centerWidget === undefined) idx--;
                    return idx;
                }
                property int nextVisibleIdx: {
                    if (!orderList.model) return -1;
                    var idx = index + 1;
                    while (idx < orderList.count && orderList.model[idx].centerWidget === undefined) idx++;
                    return idx;
                }

                // Calculate visual position (1-based) among visible items
                property int visualPos: {
                    if (!orderList.model) return 1;
                    var pos = 1;
                    for (var i = 0; i < index; i++) {
                        if (orderList.model[i].centerWidget !== undefined) pos++;
                    }
                    return pos;
                }

                Rectangle {
                    width: parent.width
                    height: 60
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    anchors.top: parent.top
                    
                    Row {
                        width: parent.width
                        height: 60
                        anchors.margins: 10
                        spacing: 12

                        // Icon based on type
                        Rectangle {
                            width: 40; height: 40
                            radius: 8
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1)
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.centerIn: parent
                                text: modelData.tabIcon !== undefined ? modelData.tabIcon : (modelData.type === "window" ? "󰖲" : "󰏗")
                                color: Theme.accent
                                font.family: Theme.fontMono
                                font.pixelSize: 18
                            }
                        }

                        // Info
                        Column {
                            width: parent.width - 40 - 12 - orderControls.width - 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: modelData.name || modelData.pluginId
                                color: Theme.textPrimary
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: "Posición: " + orderDelegate.visualPos
                                color: Theme.textMuted
                                font.family: Theme.fontSans
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Controls
                        Row {
                            id: orderControls
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Rectangle {
                                width: 28; height: 28; radius: 6
                                color: upMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                                opacity: orderDelegate.prevVisibleIdx >= 0 ? 1.0 : 0.3
                                Text { text: "↑"; font.family: Theme.fontSans; font.weight: Font.Bold; anchors.centerIn: parent; color: Theme.textPrimary; font.pixelSize: 16 }
                                MouseArea {
                                    id: upMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: orderDelegate.prevVisibleIdx >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        var pIdx = orderDelegate.prevVisibleIdx;
                                        if (pIdx >= 0 && root.shellRoot && root.shellRoot.pluginManager) {
                                            root.shellRoot.pluginManager.reorderTab(index, pIdx);
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: 28; height: 28; radius: 6
                                color: downMa.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                                opacity: orderDelegate.nextVisibleIdx >= 0 ? 1.0 : 0.3
                                Text { text: "↓"; font.family: Theme.fontSans; font.weight: Font.Bold; anchors.centerIn: parent; color: Theme.textPrimary; font.pixelSize: 16 }
                                MouseArea {
                                    id: downMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: orderDelegate.nextVisibleIdx >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        var nIdx = orderDelegate.nextVisibleIdx;
                                        if (nIdx >= 0 && root.shellRoot && root.shellRoot.pluginManager) {
                                            root.shellRoot.pluginManager.reorderTab(index, nIdx);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty state for Order View
            Item {
                width: parent.width
                height: 100
                visible: orderList.count === 0
                anchors.centerIn: parent

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "󰒍"
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: 24
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Sin widgets activos"
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
