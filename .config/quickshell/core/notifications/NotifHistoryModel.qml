import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// NotifHistoryModel – maintains a persistent list of received notifications.
QtObject {
    id: historyModel

    // ── Public history list model ────────────────────────────────────────
    property var model: ListModel { id: _model }

    signal newNotification(var entry)

    function save() {}
    function _doSave() {}
    property var _saveTimer: QtObject { function stop() {} }


    // ── Notification server (shared) ────────────────────────────────────
    required property var server

    property var _serverConnections: Connections {
        target: historyModel.server
        ignoreUnknownSignals: true

        function onNotification(notif) {
            if (notif.lastGeneration) return;

            notif.tracked = true;

            // Resolve app icon or image (unified logic)
            function resolveIcon(icon, isAppIcon) {
                if (!icon) return "";
                var s = icon.toString();
                if (s === "") return "";
                
                // If it's already a full path or a special URI, use it directly
                if (s.startsWith("/") || s.startsWith("file://") || s.startsWith("image://")) {
                    return s;
                }
                
                // Otherwise, treat as a themed icon name
                return "image://icon/" + s;
            }

            var sourceImage = resolveIcon(notif.image, false) || resolveIcon(notif.appIcon, true);
            
            // Debugging log if no image found for a known app
            if (sourceImage === "" && notif.appName !== "") {
                console.log("NotifHistoryModel: Warning - No icon resolved for app:", notif.appName, 
                            "| appIcon hint:", notif.appIcon, "| image hint:", notif.image);
            }

            var persistentImage = sourceImage;
            var isTmp = sourceImage.startsWith("file:///tmp/") || sourceImage.startsWith("/tmp/");
            if (isTmp) {
                var cacheDir = "/tmp/quickshell_notif_cache";
                Quickshell.execDetached(["mkdir", "-p", cacheDir]);
                var ts = new Date().getTime();
                var destFile = cacheDir + "/notif_" + ts + ".png";
                var srcFile = sourceImage.replace("file://", "");
                Quickshell.execDetached(["cp", srcFile, destFile]);
                persistentImage = "file://" + destFile;
            }

            var entry = {
                notifId:  notif.id,
                summary:  notif.summary  || "",
                body:     notif.body     || "",
                appName:  notif.appName  || "",
                appIcon:  notif.appIcon  || "",
                image:    persistentImage|| "",
                urgency:  notif.urgency  ?? 1,
                time:     Qt.formatTime(new Date(), "hh:mm"),
                notifRef: notif
            };

            _model.insert(0, entry);
            historyModel.newNotification(entry);

            if (_model.count > 50)
                _model.remove(_model.count - 1);
            
            historyModel.save();
        }
    }

    // ── Public functions ─────────────────────────────────────────────────
    function removeAt(index) {
        if (index < 0 || index >= _model.count) return;
        
        var entry = _model.get(index);
        var ref = entry ? entry.notifRef : null;

        // 1. Expire/Dismiss first if it's a live notification
        if (ref) {
            try { ref.expire(); } catch(e) {}
        }
        
        // 2. Clear reference before removal to help GC
        if (entry) _model.setProperty(index, "notifRef", null);
        
        // 3. Remove from model
        _model.remove(index);
        
        // 4. Schedule save
        historyModel.save();
    }

    function clearAll() {
        // Collect live refs to expire them after clearing the model
        var liveRefs = [];
        for (var i = 0; i < _model.count; i++) {
            var item = _model.get(i);
            if (item && item.notifRef) {
                liveRefs.push(item.notifRef);
            }
        }

        // 1. Clear model first to ensure UI is reset and avoiding indexing issues
        _model.clear();

        // 2. Expire live notifications
        for (var j = 0; j < liveRefs.length; j++) {
            try { liveRefs[j].expire(); } catch(e) {}
        }

        // 3. Force an immediate save for clearAll
        _saveTimer.stop();
        historyModel._doSave();
    }
}
