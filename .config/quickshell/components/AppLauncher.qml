import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Caelestia
import "../style"
// Spotlight-style unified search launcher.
// Categories: Apps, Files (plocate), Web (firefox --search), Math (qalculate).
// Prefixes: ? = web only, : = files only, = = math only, no prefix = all.
Item {
    id: launcher
    property var rootWidget

    readonly property int itemHeight: 44
    readonly property int headerHeight: 28
    readonly property int searchBarHeight: 48
    readonly property int dividerHeight: 1
    readonly property int maxApps: 5
    readonly property int maxFiles: 5
    readonly property int maxRecent: 8

    property var appResults: []
    property var fileResults: []
    property string calcResult: ""   // last qalc answer
    property bool calcPending: false  // waiting for qalc process
    property var selectableIndices: []
    property int currentSelIdx: 0

    ListModel { id: resultModel }

    AppDb {
        id: appDb
        path: Quickshell.env("HOME") + "/.cache/quickshell_appdb.sqlite"
        favouriteApps: []
        entries: DesktopEntries.applications.values
        onAppsChanged: launcher.filterApps(searchInput.text)
    }

    // ─── Initialization: ensure SQLite DB and home plocate DB exist ───────
    Process {
        id: initProc
        command: ["bash", "-c",
            // 1. Touch the SQLite file so AppDb can open it
            // 2. Create/update the home plocate DB if it's missing or >1 day old
            "db=\"$HOME/.cache/quickshell_appdb.sqlite\"; "
            + "[ -f \"$db\" ] || sqlite3 \"$db\" 'CREATE TABLE IF NOT EXISTS frequencies (id TEXT PRIMARY KEY, frequency INTEGER)' 2>/dev/null; "
            + "hdb=\"$HOME/.cache/plocate_home.db\"; "
            + "if [ ! -f \"$hdb\" ] || [ \"$(find \"$hdb\" -mtime +1 2>/dev/null)\" ]; then "
            + "  updatedb -U \"$HOME\" -o \"$hdb\" --require-visibility 0 2>/dev/null & "
            + "fi"
        ]
        running: true
    }

    // Refresh home plocate DB once per hour while the shell is running
    Timer {
        id: homeDbRefreshTimer
        interval: 3600000   // 1 hour
        repeat: true
        running: true
        onTriggered: {
            homeDbRefreshProc.running = false
            homeDbRefreshProc.running = true
        }
    }
    Process {
        id: homeDbRefreshProc
        command: ["bash", "-c",
            "updatedb -U \"$HOME\" -o \"$HOME/.cache/plocate_home.db\" --require-visibility 0 2>/dev/null"
        ]
    }

    property int preferredHeight: {
        let h = searchBarHeight + dividerHeight
        for (let i = 0; i < resultModel.count; i++)
            h += resultModel.get(i).type === "header" ? headerHeight : itemHeight
        if (resultModel.count === 0) h += itemHeight
        return Math.min(h, 520)
    }

    // Stored properties — updated imperatively by updateSearch()
    // to avoid QML binding evaluation order issues (stale last-char).
    property string searchMode: "all"
    property string cleanQuery: ""

    property string placeholderText: {
        if (searchMode === "web")   return "Search the web..."
        if (searchMode === "files") return "Search files..."
        if (searchMode === "math")  return "Enter expression (e.g. 2^10, sin(45 deg))..."
        return "Spotlight Search"
    }

    // ─── Fuzzy scoring ───────────────────────────────────────────────────
    function fuzzyScore(name, query, keywords) {
        let n = name.toLowerCase(), q = query.toLowerCase()
        if (n === q)          return 5
        if (n.startsWith(q))  return 4
        if (n.includes(q))    return 3
        if (keywords) {
            let kw = keywords.toLowerCase()
            if (kw.includes(q)) return 2
        }
        let qi = 0
        for (let i = 0; i < n.length && qi < q.length; i++)
            if (n[i] === q[qi]) qi++
        return qi === q.length ? 1 : 0
    }

    // ─── Resolve icon path directly from theme directories ───────────────
    // QIcon::fromTheme misses Papirus icons when Papirus-Dark is the active theme
    // because Papirus-Dark inherits breeze-dark,hicolor — NOT Papirus.
    // We store the raw icon name and let the delegate do layered fallback loading.
    function resolveIconPath(iconName) {
        if (!iconName) return ""
        // If it's already a full absolute path (rare, but some .desktop files do this)
        if (iconName.startsWith("/")) return iconName
        return iconName
    }

    // ─── Filter apps into appResults ─────────────────────────────────────
    function filterApps(query) {
        let q = query.trim()
        let scored = []
        for (let i = 0; i < appDb.apps.length; i++) {
            let app = appDb.apps[i]
            let sc = 0
            if (!q) {
                sc = app.frequency
                scored.push({ sc: sc, app: app })
            } else {
                sc = fuzzyScore(app.name, q, app.keywords)
                if (sc > 0) {
                    sc += app.frequency * 0.1
                    scored.push({ sc: sc, app: app })
                }
            }
        }
        scored.sort((x, y) => y.sc - x.sc || x.app.name.localeCompare(y.app.name))
        let max = q ? maxApps : maxRecent
        appResults = scored.slice(0, max).map(s => ({
            type: "app", label: s.app.name,
            icon: resolveIconPath(s.app.entry.icon || ""),
            exec: s.app.execString || "", desktop: s.app.id,
            keywords: s.app.keywords || "", terminal: s.app.entry.runInTerminal ? "true" : "false", path: "", isDir: false
        }))
        buildResults()
    }

    // ─── Build unified result model ──────────────────────────────────────
    function buildResults() {
        resultModel.clear()
        let indices = []
        let q = cleanQuery
        let mode = searchMode

        if (!q) {
            // No query → recent apps
            if (appResults.length > 0) {
                resultModel.append({ type: "header", label: "RECENT", icon: "", exec: "", desktop: "", keywords: "", terminal: "false", path: "", isDir: false })
                for (let a of appResults) {
                    indices.push(resultModel.count)
                    resultModel.append(a)
                }
            }
        } else {
            // Math result (= prefix or pending)
            if (mode === "math") {
                resultModel.append({ type: "header", label: "RESULT", icon: "", exec: "", desktop: "", keywords: "", terminal: "false", path: "", isDir: false })
                let resultLabel = calcPending ? "Calculating..." : (calcResult.length > 0 ? q + "  =  " + calcResult : "Not a valid expression")
                indices.push(resultModel.count)
                resultModel.append({
                    type: "calc", label: resultLabel, icon: "",
                    exec: "", desktop: "", keywords: "", terminal: "false", path: calcResult, isDir: false
                })
            } else {
                // Apps
                if (mode !== "web" && mode !== "files" && appResults.length > 0) {
                    resultModel.append({ type: "header", label: "APPS", icon: "", exec: "", desktop: "", keywords: "", terminal: "false", path: "", isDir: false })
                    for (let a of appResults) {
                        indices.push(resultModel.count)
                        resultModel.append(a)
                    }
                }
                // Files
                if (mode !== "web" && fileResults.length > 0) {
                    resultModel.append({ type: "header", label: "FILES", icon: "", exec: "", desktop: "", keywords: "", terminal: "false", path: "", isDir: false })
                    for (let f of fileResults) {
                        indices.push(resultModel.count)
                        resultModel.append(f)
                    }
                }
                // Web
                if (mode !== "files") {
                    resultModel.append({ type: "header", label: "WEB", icon: "", exec: "", desktop: "", keywords: "", terminal: "false", path: "", isDir: false })
                    indices.push(resultModel.count)
                    resultModel.append({
                        type: "web", label: "Search \"" + q + "\" in Firefox",
                        icon: "󰖟", exec: "firefox --search \"" + q + "\"",
                        desktop: "", keywords: "", terminal: "false", path: "", isDir: false
                    })
                }
            }
        }

        selectableIndices = indices
        if (indices.length > 0) {
            currentSelIdx = 0
            resultList.currentIndex = indices[0]
        }
    }

    // ─── Keyboard navigation (skip headers) ──────────────────────────────
    function navigateUp() {
        if (currentSelIdx > 0) {
            currentSelIdx--
            resultList.currentIndex = selectableIndices[currentSelIdx]
        }
    }
    function navigateDown() {
        if (currentSelIdx < selectableIndices.length - 1) {
            currentSelIdx++
            resultList.currentIndex = selectableIndices[currentSelIdx]
        }
    }

    // ─── Strip XDG field codes (%u, %f, %F, %U, etc.) from exec strings ─────
    function cleanExec(execStr) {
        // Remove XDG Desktop Entry Spec field codes that have no value at launch time
        return execStr.replace(/%[uUfFdDnNvmick]/g, "").replace(/\s+/g, " ").trim()
    }

    // ─── Execute selected item ───────────────────────────────────────────
    function executeItem(idx) {
        if (idx < 0 || idx >= resultModel.count) return
        let item = resultModel.get(idx)
        if (item.type === "header") return

        if (item.type === "app") {
            // Capture all needed data BEFORE incrementFrequency, which can
            // trigger onAppsChanged → buildResults() → currentSelIdx reset,
            // potentially changing resultList.currentIndex mid-execution.
            let desktopId = item.desktop
            let rawExec   = item.exec
            let isTerm    = item.terminal === "true" || item.terminal === "True"

            appDb.incrementFrequency(desktopId)

            let execCmd = cleanExec(rawExec)
            if (isTerm)
                execCmd = "kitty -e zsh -i -c '" + execCmd + "'"
            launchProc.launchCmd = execCmd
            launchProc.running = false
            launchProc.running = true
            if (rootWidget.isLauncherExpanded) rootWidget.toggleLauncherExpanded()
        } else if (item.type === "file") {
            // Open directory or select file in dolphin
            let filePath = item.path
            let isDirectory = item.isDir
            if (isDirectory) {
                launchProc.launchCmd = "dolphin \"" + filePath + "\""
            } else {
                launchProc.launchCmd = "dolphin --select \"" + filePath + "\""
            }
            launchProc.running = false
            launchProc.running = true
            if (rootWidget.isLauncherExpanded) rootWidget.toggleLauncherExpanded()
        } else if (item.type === "web") {
            launchProc.launchCmd = item.exec
            launchProc.running = false
            launchProc.running = true
            if (rootWidget.isLauncherExpanded) rootWidget.toggleLauncherExpanded()
        } else if (item.type === "calc") {
            // Copy result to clipboard — don't close launcher so user can see it
            if (item.path.length > 0) {
                clipProc.textToCopy = item.path
                clipProc.running = false
                clipProc.running = true
            }
        }
    }

    function reload() {
        searchInput.text = ""
        fileResults = []
        filterApps("")
        focusTimer.start()
    }

    function updateSearch() {
        // Compute mode & query imperatively from the *current* text
        // (avoids stale binding reads that drop the last character).
        let raw = searchInput.text.trim()
        if (raw.startsWith("?"))      { searchMode = "web";   cleanQuery = raw.substring(1).trim() }
        else if (raw.startsWith(":")) { searchMode = "files"; cleanQuery = raw.substring(1).trim() }
        else if (raw.startsWith("=")) { searchMode = "math";  cleanQuery = raw.substring(1).trim() }
        else                          { searchMode = "all";   cleanQuery = raw }

        let q = cleanQuery
        let mode = searchMode

        if (mode === "math") {
            calcResult = ""
            if (q.length >= 1) {
                calcPending = true
                buildResults()
                calcDebounce.restart()
            } else {
                calcPending = false
                buildResults()
            }
            return
        }

        calcResult = ""
        calcPending = false

        if (mode !== "web" && mode !== "files")
            filterApps(q)
        else {
            appResults = []
            buildResults()
        }
        // Trigger file search with debounce
        if (q.length >= 2 && mode !== "web")
            fileDebounce.restart()
        else {
            fileResults = []
            buildResults()
        }
    }

    Timer { id: focusTimer; interval: 80; onTriggered: searchInput.forceActiveFocus() }

    Timer {
        id: fileDebounce
        interval: 200
        onTriggered: {
            let q = launcher.cleanQuery
            if (q.length >= 2) {
                fileSearchProc.running = false
                fileSearchProc.running = true
            }
        }
    }

    Timer {
        id: calcDebounce
        interval: 300
        onTriggered: {
            let q = launcher.cleanQuery
            if (q.length >= 1 && launcher.searchMode === "math") {
                Qalculator.evalAsync(q)
            }
        }
    }

    // ─── Processes ───────────────────────────────────────────────────────

    Process {
        id: launchProc
        property string launchCmd: ""
        command: ["hyprctl", "dispatch", "hl.dsp.exec_cmd([[" + launchCmd + "]])"]
    }

    Process {
        id: clipProc
        property string textToCopy: ""
        command: ["bash", "-c", "printf '%s' " + JSON.stringify(textToCopy) + " | wl-copy"]
    }

    Connections {
        target: Qalculator
        function onRawResultChanged() {
            if (launcher.searchMode !== "math") return;
            let raw = Qalculator.rawResult.trim()
            let q = launcher.cleanQuery.trim()
            if (raw.length > 0 && raw !== q && raw !== "error") {
                launcher.calcResult = raw
            } else {
                launcher.calcResult = ""
            }
            launcher.buildResults()
        }
        function onBusyChanged() {
            if (launcher.searchMode !== "math") return;
            launcher.calcPending = Qalculator.busy
            launcher.buildResults()
        }
    }


    Process {
        id: fileSearchProc
        // Two-phase search: home directory first (using personal plocate DB),
        // then supplement with the system DB — so home results always appear first.
        // Home DB is created/updated by initProc / homeDbRefreshTimer.
        command: ["bash", "-c",
            "q=$1; HOME_DB=\"$HOME/.cache/plocate_home.db\"; SYS_DB=/var/lib/plocate/plocate.db; "
            // Phase 1: search home DB (max 5 results)
            + "if [ -f \"$HOME_DB\" ]; then "
            + "  mapfile -t home_res < <(plocate -d \"$HOME_DB\" -i -l 5 \"$q\" 2>/dev/null); "
            + "else home_res=(); fi; "
            // Phase 2: search system DB (skip paths already in home results, max to fill up to 8 total)
            + "remain=$((8 - ${#home_res[@]})); "
            + "if [ $remain -gt 0 ] && [ -f \"$SYS_DB\" ]; then "
            + "  mapfile -t sys_res < <(plocate -d \"$SYS_DB\" -i -l $((remain * 4)) \"$q\" 2>/dev/null "
            + "    | grep -v \"^$HOME/\" | head -n $remain); "
            + "else sys_res=(); fi; "
            // Output: home results first, then system results
            + "printf '%s\\n' \"${home_res[@]}\" \"${sys_res[@]}\" | grep -v '^$'",
            "_", launcher.cleanQuery
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n").filter(l => l.length > 0)
                let results = []
                for (let line of lines) {
                    let parts = line.split("/")
                    let basename = parts[parts.length - 1]
                    results.push({
                        type: "file",
                        label: basename,
                        icon: "󰈔",   // overridden in delegate based on isDir
                        exec: "", desktop: "", keywords: "", terminal: "false",
                        path: line,
                        isDir: false   // filled in by statProc below
                    })
                }
                launcher.fileResults = results
                if (lines.length > 0) {
                    statProc.pathList = lines.join("\n")
                    statProc.running = false
                    statProc.running = true
                } else {
                    launcher.buildResults()
                }
            }
        }
    }

    // Stat check: determine which paths are directories
    // Uses newline separator so paths with spaces are handled correctly.
    Process {
        id: statProc
        property string pathList: ""   // newline-joined list of paths
        command: ["bash", "-c",
            "printf '%s\\n' \"$1\" | while IFS= read -r p; do [ -z \"$p\" ] && continue; [ -d \"$p\" ] && echo \"DIR:$p\" || echo \"FILE:$p\"; done",
            "_", pathList]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n").filter(l => l.length > 0)
                let dirSet = {}
                for (let line of lines) {
                    if (line.startsWith("DIR:")) dirSet[line.substring(4)] = true
                }
                // Update isDir on fileResults
                let updated = []
                for (let r of launcher.fileResults) {
                    let copy = Object.assign({}, r)
                    copy.isDir = dirSet[r.path] === true
                    updated.push(copy)
                }
                launcher.fileResults = updated
                launcher.buildResults()
            }
        }
    }

    // ─── UI ──────────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        spacing: 0

        // ── Search bar ───────────────────────────────────────────
        Row {
            width: parent.width
            height: searchBarHeight
            spacing: 12

            Text {
                text: "󰍉"
                font.family: "Iosevka Nerd Font"
                font.pixelSize: 20
                color: Theme.textPrimary
                opacity: 0.5
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: parent.width - 32 - 12
                height: parent.height

                Text {
                    visible: searchInput.text.length === 0
                    text: launcher.placeholderText
                    font.family: "JetBrains Mono"
                    font.pixelSize: 14
                    color: Theme.textPrimary
                    opacity: 0.35
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    font.family: "JetBrains Mono"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: Theme.textPrimary
                    verticalAlignment: TextInput.AlignVCenter
                    selectionColor: Qt.rgba(
                        Theme.accent.r,
                        Theme.accent.g,
                        Theme.accent.b, 0.35
                    )
                    onTextChanged: launcher.updateSearch()
                    Keys.onUpPressed:     function(event) { launcher.navigateUp(); event.accepted = true }
                    Keys.onDownPressed:   function(event) { launcher.navigateDown(); event.accepted = true }
                    Keys.onReturnPressed: function(event) { launcher.executeItem(resultList.currentIndex); event.accepted = true }
                    Keys.onEscapePressed: function(event) { if (rootWidget.isLauncherExpanded) rootWidget.toggleLauncherExpanded(); event.accepted = true }
                    Keys.onTabPressed:    function(event) { launcher.navigateDown(); event.accepted = true }
                }
            }
        }

        // ── Divider ──────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: dividerHeight
            color: Qt.rgba(
                Theme.textPrimary.r,
                Theme.textPrimary.g,
                Theme.textPrimary.b, 0.12
            )
        }

        // ── Results ──────────────────────────────────────────────
        ListView {
            id: resultList
            width: parent.width
            height: parent.height - (searchBarHeight + dividerHeight)
            clip: true
            model: resultModel
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

            // Empty state
            Text {
                anchors.centerIn: parent
                visible: resultModel.count === 0 && searchInput.text.length > 0
                text: "No results found"
                font.family: "JetBrains Mono"
                font.pixelSize: 13
                color: Theme.textPrimary
                opacity: 0.35
            }

            delegate: Loader {
                width: resultList.width
                height: model.type === "header" ? headerHeight : itemHeight
                sourceComponent: model.type === "header" ? headerDelegate : itemDelegate

                Component {
                    id: headerDelegate
                    Item {
                        width: resultList.width
                        height: headerHeight
                        Text {
                            text: model.label
                            font.family: "JetBrains Mono"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                            color: Theme.textPrimary
                            opacity: 0.35
                            anchors {
                                left: parent.left; leftMargin: 4
                                bottom: parent.bottom; bottomMargin: 4
                            }
                        }
                    }
                }

                Component {
                    id: itemDelegate
                    Rectangle {
                        width: resultList.width
                        height: itemHeight
                        radius: 10
                        color: resultList.currentIndex === index
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                            : itemHover.containsMouse
                                ? Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.06)
                                : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            anchors { left: parent.left; right: parent.right; margins: 10; verticalCenter: parent.verticalCenter }
                            spacing: 12

                            // Icon area — parallel multi-source fallback:
                            //   1. Papirus 64x64 SVG  (covers ~8000 apps, best quality)
                            //   2. hicolor 128x128 PNG (upstream bundled icons, e.g. Firefox)
                            //   3. hicolor 48x48 PNG
                            //   4. /usr/share/pixmaps PNG
                            //   5. Nerd font glyph fallback
                            // All sources load in parallel; highest-priority Ready layer wins.
                            Item {
                                id: iconArea
                                width: 28; height: 28
                                anchors.verticalCenter: parent.verticalCenter
                                visible: model.type === "app"

                                readonly property string ic: model.icon || ""

                                // Layer 1: Papirus SVG 64x64 (preferred)
                                Image {
                                    id: iconP64
                                    anchors.fill: parent
                                    source: iconArea.ic ? "file:///usr/share/icons/Papirus/64x64/apps/" + iconArea.ic + ".svg" : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true; smooth: true
                                    visible: status === Image.Ready
                                }
                                // Layer 2: hicolor 128x128 PNG
                                Image {
                                    id: iconHi128
                                    anchors.fill: parent
                                    source: iconArea.ic ? "file:///usr/share/icons/Papirus/128x128/apps/" + iconArea.ic + ".png" : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true; smooth: true
                                    visible: status === Image.Ready && !iconP64.visible
                                }
                                // Layer 3: hicolor 48x48 PNG
                                Image {
                                    id: iconHi48
                                    anchors.fill: parent
                                    source: iconArea.ic ? "file:///usr/share/pixmaps/" + iconArea.ic + ".png" : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true; smooth: true
                                    visible: status === Image.Ready && !iconP64.visible && !iconHi128.visible
                                }
                                // Layer 4: pixmaps PNG
                                Image {
                                    id: iconPixmap
                                    anchors.fill: parent
                                    source: iconArea.ic ? "file:///usr/share/pixmaps/" + iconArea.ic + ".svg" : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true; smooth: true
                                    visible: status === Image.Ready && !iconP64.visible && !iconHi128.visible && !iconHi48.visible
                                }
                                // Layer 5: Nerd font glyph (last resort)
                                Text {
                                    anchors.centerIn: parent
                                    visible: iconArea.ic.length > 0
                                         && !iconP64.visible && !iconHi128.visible && !iconHi48.visible && !iconPixmap.visible
                                         && iconP64.status !== Image.Loading
                                    text: "󰣆"
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: 18
                                    color: Theme.textPrimary
                                    opacity: 0.4
                                }
                            }

                            // Nerd font icon for file / dir / web / calc
                            Text {
                                visible: model.type === "file" || model.type === "web" || model.type === "calc"
                                text: {
                                    if (model.type === "web")  return "󰖟"
                                    if (model.type === "calc") return "󰪚"
                                    return model.isDir ? "󰉋" : "󰈔"
                                }
                                font.family: "Iosevka Nerd Font"
                                font.pixelSize: 18
                                color: resultList.currentIndex === index
                                    ? Theme.accent
                                    : Theme.textPrimary
                                opacity: resultList.currentIndex === index ? 1.0 : 0.6
                                width: 28
                                horizontalAlignment: Text.AlignHCenter
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Label column
                            Column {
                                width: parent.width - 28 - 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: model.label
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: resultList.currentIndex === index
                                        ? Theme.accent
                                        : Theme.textPrimary
                                    opacity: resultList.currentIndex === index ? 1.0 : 0.75
                                    elide: Text.ElideRight
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                // Subtitle: directory path for files, "Copy to clipboard" for calc
                                Text {
                                    visible: (model.type === "file" && model.path.length > 0)
                                             || model.type === "calc"
                                    width: parent.width
                                    text: {
                                        if (model.type === "calc") return "Press Enter to copy result"
                                        if (model.type !== "file" || !model.path) return ""
                                        let parts = model.path.split("/")
                                        parts.pop()
                                        return parts.join("/").replace(/^\/home\/[^/]+/, "~")
                                    }
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 10
                                    color: Theme.textPrimary
                                    opacity: 0.35
                                    elide: Text.ElideMiddle
                                }
                            }
                        }

                        MouseArea {
                            id: itemHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: launcher.executeItem(index)
                        }
                    }
                }
            }
        }
    }
}
