import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../../style"

Item {
    id: root

    property var shellRoot: null

    property var tagsDb: ({})
    property string searchQuery: ""
    property bool isTagging: false

    property var taggingStatusProcess: Process {
        command: ["bash", "-c", "while true; do if [ -f ~/.cache/wallpaper/tagger.lock ]; then echo '1'; else echo '0'; fi; sleep 2; done"]
        running: true
        stdout: SplitParser {
            splitMarker: ""
            onRead: (data) => {
                let text = data.trim();
                if (text === "1") root.isTagging = true;
                else if (text === "0") root.isTagging = false;
            }
        }
    }

    property var loadTagsProcess: Process {
        command: ["cat", Quickshell.env("HOME") + "/.cache/wallpaper/tags.json"]
        running: false

        stdout: SplitParser {
            splitMarker: ""
            onRead: (data) => {
                let text = data.trim();
                if (text.length > 0) {
                    try {
                        root.tagsDb = JSON.parse(text);
                        root.rebuildFilter();
                    } catch (e) {
                        console.log("Failed to parse tags.json:", e);
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        loadTagsProcess.running = true;
    }

    property string targetWallName: ""
    property var currentWallProcess: Process {
        command: ["bash", "-c", "awww query | grep 'currently displaying' | sed -E 's/.*image: (.*)/\\1/' | head -n 1 || true"]
        running: true
        stdout: SplitParser {
            onRead: (data) => {
                let text = data.trim();
                let parts = text.split('/');
                let name = parts[parts.length - 1];
                if (name && name !== "black.jpg") {
                    root.targetWallName = name;
                    root.tryFocus();
                }
            }
        }
    }

    readonly property string homeDir: "file://" + Quickshell.env("HOME")
    readonly property string thumbDir: homeDir + "/.cache/wallpaper"
    readonly property string srcDir: Quickshell.env("HOME") + "/wallpaper"
    readonly property string awwwCommand: "awww img '%1' --transition-type %2 --transition-pos top --transition-fps 60 --transition-duration 2"
    readonly property var transitions: ["grow"]
    readonly property int itemWidthExpanded: 650
    readonly property int itemWidthCollapsed: 80
    readonly property int itemHeight: 380

    property var filteredIndices: []
    property bool searchFocused: false
    property bool initialFocusSet: false

    function getTagsForFile(fileName) {
        if (root.tagsDb && root.tagsDb[fileName]) return root.tagsDb[fileName];
        return [];
    }

    function matchesSearch(fileName) {
        let q = root.searchQuery.trim().toLowerCase();
        if (q === "") return true;
        let terms = q.split(/\s+/);
        let tags = getTagsForFile(fileName);
        let tagStr = tags.join(" ");
        let nameStr = fileName.toLowerCase();
        for (let t of terms) {
            if (tagStr.indexOf(t) === -1 && nameStr.indexOf(t) === -1)
                return false;
        }
        return true;
    }

    function rebuildFilter() {
        let indices = [];
        for (let i = 0; i < folderModel.count; i++) {
            let fname = folderModel.get(i, "fileName");
            if (matchesSearch(fname)) indices.push(i);
        }
        filteredIndices = indices;
    }

    function tryFocus() {
        if (!initialFocusSet && targetWallName !== "" && view.count > 0) {
            let foundIndex = -1;
            for (let i = 0; i < view.count; i++) {
                let fname = (root.searchQuery !== "" ? filteredModel.get(i).fileName : folderModel.get(i, "fileName"));
                if (fname === targetWallName || fname === "000_" + targetWallName) {
                    foundIndex = i;
                    break;
                }
            }
            if (foundIndex !== -1) {
                view.currentIndex = foundIndex;
                initialFocusSet = true;
            }
        }
    }

    Connections {
        target: root
        function onSearchQueryChanged() {
            root.rebuildFilter();
            if (view.count > 0) view.currentIndex = 0;
        }
    }

    Connections {
        target: root.shellRoot
        ignoreUnknownSignals: true
        function onWallpaperOpenChanged() {
            if (root.shellRoot && root.shellRoot.wallpaperOpen) {
                view.forceActiveFocus();
                root.searchFocused = false;
            }
        }
    }

    Shortcut {
        sequence: "Left"
        enabled: !root.searchFocused && root.shellRoot && root.shellRoot.wallpaperOpen
        onActivated: view.decrementCurrentIndex()
    }
    Shortcut {
        sequence: "Right"
        enabled: !root.searchFocused && root.shellRoot && root.shellRoot.wallpaperOpen
        onActivated: view.incrementCurrentIndex()
    }
    Shortcut {
        sequence: "Return"
        enabled: !root.searchFocused && root.shellRoot && root.shellRoot.wallpaperOpen
        onActivated: {
            if (view.currentItem) view.currentItem.pickWallpaper();
        }
    }
    Shortcut {
        sequence: "Ctrl+F"
        enabled: root.shellRoot && root.shellRoot.wallpaperOpen
        onActivated: {
            searchField.forceActiveFocus();
            searchField.selectAll();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // Search Bar Row
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 400
            Layout.preferredHeight: 30
            Layout.maximumHeight: 30
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 430
                Layout.fillHeight: true
                radius: 22
                color: root.searchFocused ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15) : Theme.bgPill
                border.color: root.searchFocused ? Theme.accent : Qt.rgba(1, 1, 1, 0.1)
                border.width: 1

                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Item {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        id: searchIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "⌕"
                        color: root.searchFocused ? Theme.accent : Theme.textMuted
                        font.pixelSize: 18
                    }

                    TextInput {
                        id: searchField
                        anchors.left: searchIcon.right
                        anchors.leftMargin: 8
                        anchors.right: clearBtn.visible ? clearBtn.left : parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.family: Theme.fontSans
                        clip: true
                        selectByMouse: true
                        selectedTextColor: "black"
                        selectionColor: Theme.accent

                        onTextChanged: root.searchQuery = text
                        onActiveFocusChanged: root.searchFocused = activeFocus

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Buscar por tags... (Ctrl+F)"
                            color: Theme.textMuted
                            font: parent.font
                            visible: !parent.text && !parent.activeFocus
                        }
                    }

                    // Clear button
                    Rectangle {
                        id: clearBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 10
                        color: clearMa.containsMouse ? Qt.rgba(1,1,1,0.2) : "transparent"
                        visible: searchField.text.length > 0
                        
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: Theme.textMuted
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: clearMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                searchField.text = "";
                                root.searchQuery = "";
                                view.forceActiveFocus();
                            }
                        }
                    }
                }
            }
            
            // Tagging Indicator
            RowLayout {
                visible: root.isTagging
                spacing: 6
                Rectangle {
                    width: 8; height: 8; radius: 4; color: Theme.accent
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: root.isTagging
                        NumberAnimation { to: 0.3; duration: 800 }
                        NumberAnimation { to: 1.0; duration: 800 }
                    }
                }
                Text {
                    text: "Generando tags..."
                    color: Theme.accent
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }
        }

        // List View
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: view
                anchors.fill: parent
                spacing: 12
                orientation: ListView.Horizontal
                clip: true
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width / 2) - (root.itemWidthExpanded / 2)
                preferredHighlightEnd: (width / 2) + (root.itemWidthExpanded / 2)
                highlightMoveDuration: 250

                model: root.searchQuery !== "" ? filteredModel : folderModel

                FolderListModel {
                    id: folderModel
                    folder: root.thumbDir
                    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif"]
                    showDirs: false
                    sortField: FolderListModel.Name
                    onStatusChanged: {
                        root.rebuildFilter();
                        root.tryFocus();
                    }
                    onCountChanged: root.rebuildFilter()
                }

                ListModel { id: filteredModel }

                Connections {
                    target: root
                    function onFilteredIndicesChanged() {
                        filteredModel.clear();
                        for (let idx of root.filteredIndices) {
                            filteredModel.append({
                                fileName: folderModel.get(idx, "fileName"),
                                fileUrl: folderModel.get(idx, "fileUrl")
                            });
                        }
                    }
                }

                delegate: Item {
                    id: delegateRoot
                    readonly property bool isCurrent: ListView.isCurrentItem
                    readonly property var currentTags: root.getTagsForFile(fileName)

                    width: isCurrent ? root.itemWidthExpanded : root.itemWidthCollapsed
                    height: view.height
                    z: isCurrent ? 10 : 1

                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

                    function pickWallpaper() {
                        const originalFile = root.srcDir + "/" + fileName;
                        // Kill wallpaper engine si estuviera corriendo
                        Quickshell.execDetached(["bash", "-c", "killall linux-wallpaperengine || true"]);
                        const randomTransition = root.transitions[Math.floor(Math.random() * root.transitions.length)];
                        const finalCmd = root.awwwCommand.arg(originalFile).arg(randomTransition);
                        Quickshell.execDetached(["bash", "-c", finalCmd]);
                        const postCmd = "sleep 2 && /home/luisp/.config/hypr/scripts_hypr/update_color.sh '" + originalFile + "'";
                        Quickshell.execDetached(["bash", "-c", postCmd]);
                        
                        if (root.shellRoot) {
                            root.shellRoot.wallpaperOpen = false;
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (view.currentIndex === index) {
                                delegateRoot.pickWallpaper();
                            } else {
                                view.currentIndex = index;
                            }
                        }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: parent.width
                        height: root.itemHeight
                        opacity: delegateRoot.isCurrent ? 1 : 0.4
                        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }

                        Rectangle {
                            anchors.fill: parent
                            radius: delegateRoot.isCurrent ? 18 : 10
                            color: delegateRoot.isCurrent ? Theme.accent : Theme.bgPill
                            border.color: delegateRoot.isCurrent ? Theme.accent : "transparent"
                            border.width: delegateRoot.isCurrent ? 2 : 0
                            Behavior on radius { NumberAnimation { duration: 250 } }
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }

                        Item {
                            anchors.fill: parent
                            anchors.margins: delegateRoot.isCurrent ? 6 : 2
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: delegateRoot.isCurrent ? 14 : 8
                                color: "black"
                            }

                            Image {
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.height
                                fillMode: Image.PreserveAspectCrop
                                source: fileUrl
                                sourceSize.height: root.itemHeight
                                cache: true
                                asynchronous: true
                            }
                        }

                        // Tags Overlay (solo en el expandido)
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: tagsFlow.implicitHeight + 20
                            color: Qt.rgba(0, 0, 0, 0.75)
                            radius: 14
                            visible: delegateRoot.isCurrent && delegateRoot.currentTags.length > 0
                            opacity: visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 250 } }

                            Flow {
                                id: tagsFlow
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Repeater {
                                    model: delegateRoot.currentTags
                                    Rectangle {
                                        width: tagLabel.implicitWidth + 14
                                        height: 22
                                        radius: 11
                                        color: {
                                            let q = root.searchQuery.trim().toLowerCase();
                                            if (q !== "" && modelData.indexOf(q) !== -1)
                                                return Theme.accent;
                                            return Qt.rgba(1, 1, 1, 0.15);
                                        }
                                        Behavior on color { ColorAnimation { duration: 150 } }

                                        Text {
                                            id: tagLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: {
                                                let q = root.searchQuery.trim().toLowerCase();
                                                if (q !== "" && modelData.indexOf(q) !== -1)
                                                    return "#000000";
                                                return Theme.textPrimary;
                                            }
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                searchField.text = modelData;
                                                root.searchQuery = modelData;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
