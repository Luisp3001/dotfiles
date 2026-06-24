// components/PluginManager.qml — Dynamic plugin loader/unloader
// Reads plugins.json, loads enabled plugins via Qt.createComponent(),
// and provides IPC commands for enable/disable/uninstall.
//
// Usage:
//   quickshell ipc call plugins list
//   quickshell ipc call plugins enable  "com.luisp.dock"
//   quickshell ipc call plugins disable "com.luisp.dock"
//   quickshell ipc call plugins uninstall "com.luisp.dock"
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: pluginManager
    visible: false

    signal settingChanged(string pluginId, string key, var value)

    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"

    // ── Active plugin tracking ───────────────────────────────────────────
    // Maps plugin id → { component: Component, object: QObject }
    property var _activeComponents: ({})
    property var _activeObjects: ({})
    property var activeWidgets: [] // Lista de QObjects de tipo widget
    property var tabOrder: []    // Persistent custom tab order (array of plugin IDs)

    // Active widgets sorted by user-defined tab order
    property var orderedWidgets: {
        var _w = activeWidgets;
        var _t = tabOrder;
        var ordered = [];
        var remaining = _w.slice();
        for (var i = 0; i < _t.length; i++) {
            for (var j = 0; j < remaining.length; j++) {
                if (remaining[j].pluginId === _t[i]) {
                    ordered.push(remaining[j]);
                    remaining.splice(j, 1);
                    break;
                }
            }
        }
        for (var k = 0; k < remaining.length; k++) {
            ordered.push(remaining[k]);
        }
        return ordered;
    }
    property bool _registryLoaded: false
    property alias model: pluginModel
    property var shellRoot: null
    property int activePluginsCount: 0

    // ── Plugin registry model ────────────────────────────────────────────
    ListModel {
        id: pluginModel
        // Each entry: { id, path, enabled, name, main, type }
    }

    property bool _registryFileReady: false
    function _tryStart() {
        if (_registryFileReady && _settingsLoaded && !_registryLoaded) {
            _loadRegistry()
        }
    }

    // ── Read plugins.json ────────────────────────────────────────────────
    FileView {
        id: registryFile
        path: pluginManager.configDir + "/plugins.json"
        onLoaded: {
            pluginManager._registryFileReady = true
            pluginManager._tryStart()
        }
        onLoadFailed: (err) => {
            if (err === FileViewError.FileNotFound) {
                console.log("PluginManager: No plugins.json found, creating empty registry")
                Qt.callLater(() => {
                    setText(JSON.stringify({ installed: [] }, null, 2))
                    pluginManager._registryLoaded = true  // Allow saves now that file is initialised
                    pluginManager._registryFileReady = true
                    pluginManager._tryStart()
                })
            }
        }
    }

    // ── Persist changes (debounced) ──────────────────────────────────────
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: pluginManager._saveRegistry()
    }

    // ── Process for uninstall (rm -rf) ───────────────────────────────────
    Process {
        id: uninstallProc
        onExited: (code) => {
            if (code === 0)
                console.log("PluginManager: Plugin files removed successfully")
            else
                console.error("PluginManager: Failed to remove plugin files (exit code " + code + ")")
        }
    }

    // ── Plugin Settings ──────────────────────────────────────────────────
    property var _pluginSettings: ({})
    property bool _settingsLoaded: false

    FileView {
        id: settingsFile
        path: pluginManager.configDir + "/plugin_settings.json"
        onLoaded: {
            pluginManager._loadSettings()
            pluginManager._tryStart()
        }
        onLoadFailed: (err) => {
            if (err === FileViewError.FileNotFound) {
                console.log("PluginManager: No plugin_settings.json found, creating empty registry")
                Qt.callLater(() => {
                    setText("{}")
                    pluginManager._settingsLoaded = true
                    pluginManager._tryStart()
                })
            }
        }
    }

    Timer {
        id: settingsSaveTimer
        interval: 500
        onTriggered: pluginManager._saveSettings()
    }

    // ── IPC Handler ──────────────────────────────────────────────────────
    // Control plugins from terminal: quickshell ipc call plugins <function> [args]
    IpcHandler {
        target: "plugins"

        function list(): string {
            return pluginManager._listPlugins()
        }

        function enable(pluginId: string): string {
            return pluginManager._setEnabled(pluginId, true)
        }

        function disable(pluginId: string): string {
            return pluginManager._setEnabled(pluginId, false)
        }

        function uninstall(pluginId: string): string {
            return pluginManager._uninstall(pluginId)
        }
    }

    // ── Public API ───────────────────────────────────────────────────────
    
    // Registers a plugin in the model, persists, and activates it.
    function installPlugin(id, path, name, main, type) {
        // Check if already installed
        for (var i = 0; i < pluginModel.count; i++) {
            if (pluginModel.get(i).id === id) {
                console.log("PluginManager: Plugin already installed: " + id)
                // Re-enable if disabled
                return _setEnabled(id, true)
            }
        }

        // Add to model
        pluginModel.append({
            id:      id,
            path:    path,
            enabled: true,
            name:    name || id,
            main:    main || "Main.qml",
            type:    type || "window"
        })

        // Activate
        _activatePlugin(id, path, main || "Main.qml", type || "window")

        // Persist
        saveTimer.restart()
        console.log("PluginManager: ✓ Installed plugin: " + id)
        return id + " installed"
    }

    function setPluginEnabled(id, enabled) {
        return _setEnabled(id, enabled)
    }

    function uninstallPlugin(id) {
        return _uninstall(id)
    }

    function getSetting(pluginId, key, defaultValue) {
        if (_pluginSettings[pluginId] && _pluginSettings[pluginId][key] !== undefined) {
            return _pluginSettings[pluginId][key]
        }
        return defaultValue
    }

    function setSetting(pluginId, key, value) {
        if (!_pluginSettings[pluginId]) {
            var newSettings = Object.assign({}, _pluginSettings)
            newSettings[pluginId] = {}
            _pluginSettings = newSettings
        }
        if (_pluginSettings[pluginId][key] !== value) {
            var updatedSettings = Object.assign({}, _pluginSettings)
            updatedSettings[pluginId][key] = value
            _pluginSettings = updatedSettings
            settingsSaveTimer.restart()
            pluginManager.settingChanged(pluginId, key, value)
        }
    }

    function reorderTab(fromIndex, toIndex) {
        var widgets = orderedWidgets.slice();
        if (fromIndex < 0 || fromIndex >= widgets.length || toIndex < 0 || toIndex >= widgets.length) return;
        if (fromIndex === toIndex) return;
        var item = widgets.splice(fromIndex, 1)[0];
        widgets.splice(toIndex, 0, item);
        var newOrder = widgets.map(function(w) { return w.pluginId; });
        tabOrder = newOrder;
        var settings = Object.assign({}, _pluginSettings);
        settings.__tabOrder = newOrder;
        _pluginSettings = settings;
        settingsSaveTimer.restart();
    }


    // ══════════════════════════════════════════════════════════════════════
    // ── Internal functions ───────────────────────────────────────────────
    // ══════════════════════════════════════════════════════════════════════

    function _loadRegistry() {
        try {
            var data = JSON.parse(registryFile.text())
            var installed = data.installed || []

            for (var i = 0; i < installed.length; i++) {
                var entry = installed[i]
                pluginModel.append({
                    id:      entry.id || "",
                    path:    entry.path || "",
                    enabled: entry.enabled !== false,
                    name:    entry.name || entry.id || "",
                    main:    entry.main || "Main.qml",
                    type:    entry.type || "window"
                })

                // Activate enabled plugins (window or widget)
                if (entry.enabled !== false) {
                    _activatePlugin(entry.id, entry.path, entry.main || "Main.qml", entry.type || "window")
                }
            }

            console.log("PluginManager: Loaded " + installed.length + " plugin(s)")
            _registryLoaded = true
        } catch (e) {
            console.error("PluginManager: Failed to parse registry: " + e)
            _registryLoaded = true  // Still allow saves even if parse failed
        }
    }

    function _activatePlugin(id, path, main, type) {
        if (_activeObjects[id]) {
            console.log("PluginManager: Plugin already active: " + id)
            return
        }

        var qmlUrl = "file://" + configDir + "/" + path + "/" + main
        console.log("PluginManager: Loading plugin: " + id + " from " + qmlUrl)

        var component = Qt.createComponent(qmlUrl)

        if (component.status === Component.Ready) {
            _finishActivation(id, component, type)
        } else if (component.status === Component.Error) {
            console.error("PluginManager: ✗ Failed to load " + id + ": " + component.errorString())
        } else {
            // Component loading asynchronously
            component.statusChanged.connect(function() {
                if (component.status === Component.Ready) {
                    _finishActivation(id, component, type)
                } else if (component.status === Component.Error) {
                    console.error("PluginManager: ✗ Failed to load " + id + " (async): " + component.errorString())
                }
            })
        }
    }

    function _finishActivation(id, component, type) {
        var obj = component.createObject(pluginManager, { "pluginId": id })
        if (obj) {
            var newComponents = Object.assign({}, _activeComponents)
            newComponents[id] = component
            _activeComponents = newComponents
            
            var newObjects = Object.assign({}, _activeObjects)
            newObjects[id] = obj
            _activeObjects = newObjects
            
            // Si es widget, añadirlo a la lista de activeWidgets
            if (type === "widget") {
                var wlist = activeWidgets.slice()
                wlist.push(obj)
                activeWidgets = wlist
            }
            
            pluginManager.activePluginsCount = Object.keys(_activeObjects).length
            console.log("PluginManager: ✓ Activated plugin: " + id)
        } else {
            console.error("PluginManager: ✗ Failed to create object for: " + id)
        }
    }

    function _deactivatePlugin(id) {
        if (_activeObjects[id]) {
            // Eliminar de activeWidgets si era un widget
            var wlist = activeWidgets.slice()
            for (var i = 0; i < wlist.length; i++) {
                if (wlist[i].pluginId === id) {
                    wlist.splice(i, 1)
                    break
                }
            }
            activeWidgets = wlist

            _activeObjects[id].destroy()
            var newObjects = Object.assign({}, _activeObjects)
            delete newObjects[id]
            _activeObjects = newObjects
            pluginManager.activePluginsCount = Object.keys(_activeObjects).length
        }
        if (_activeComponents[id]) {
            var newComponents = Object.assign({}, _activeComponents)
            delete newComponents[id]
            _activeComponents = newComponents
        }
        console.log("PluginManager: Deactivated plugin: " + id)
    }

    function _setEnabled(pluginId, enabled) {
        for (var i = 0; i < pluginModel.count; i++) {
            var p = pluginModel.get(i)
            if (p.id === pluginId) {
                pluginModel.setProperty(i, "enabled", enabled)

                if (enabled) {
                    _activatePlugin(p.id, p.path, p.main, p.type)
                } else {
                    _deactivatePlugin(pluginId)
                }

                saveTimer.restart()
                return pluginId + " " + (enabled ? "enabled" : "disabled")
            }
        }
        return "ERROR: Plugin not found: " + pluginId
    }

    function _uninstall(pluginId) {
        for (var i = 0; i < pluginModel.count; i++) {
            var p = pluginModel.get(i)
            if (p.id === pluginId) {
                // Deactivate first
                _deactivatePlugin(pluginId)

                // Clean up tab order
                var oi = tabOrder.indexOf(pluginId)
                if (oi !== -1) {
                    var newOrder = tabOrder.slice()
                    newOrder.splice(oi, 1)
                    tabOrder = newOrder
                    var s = Object.assign({}, _pluginSettings)
                    s.__tabOrder = newOrder
                    _pluginSettings = s
                    settingsSaveTimer.restart()
                }

                // Remove plugin directory
                var pluginPath = configDir + "/" + p.path
                uninstallProc.command = ["rm", "-rf", pluginPath]
                uninstallProc.running = true

                // Remove from model and persist
                pluginModel.remove(i)
                saveTimer.restart()
                return "Uninstalled " + pluginId
            }
        }
        return "ERROR: Plugin not found: " + pluginId
    }

    function _listPlugins() {
        var lines = []
        for (var i = 0; i < pluginModel.count; i++) {
            var p = pluginModel.get(i)
            var status = p.enabled ? "✓ enabled" : "✗ disabled"
            var active = _activeObjects[p.id] ? " (active)" : ""
            lines.push(p.id + " [" + status + active + "] " + (p.name || ""))
        }
        if (lines.length === 0) return "No plugins installed"
        return lines.join("\n")
    }

    function _saveRegistry() {
        if (!_registryLoaded) return  // Don't overwrite during init

        var data = { installed: [] }
        for (var i = 0; i < pluginModel.count; i++) {
            var p = pluginModel.get(i)
            data.installed.push({
                id:      p.id,
                path:    p.path,
                enabled: p.enabled,
                name:    p.name,
                main:    p.main,
                type:    p.type
            })
        }
        registryFile.setText(JSON.stringify(data, null, 2))
    }

    function _loadSettings() {
        try {
            _pluginSettings = JSON.parse(settingsFile.text())
            _settingsLoaded = true
            if (_pluginSettings.__tabOrder && Array.isArray(_pluginSettings.__tabOrder)) {
                tabOrder = _pluginSettings.__tabOrder;
            }
            console.log("PluginManager: Settings loaded")
        } catch (e) {
            console.error("PluginManager: Failed to parse settings: " + e)
            _pluginSettings = {}
            _settingsLoaded = true
        }
    }

    function _saveSettings() {
        if (!_settingsLoaded) return
        settingsFile.setText(JSON.stringify(_pluginSettings, null, 2))
    }
}
