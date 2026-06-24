import QtQuick
import Quickshell.Services.Notifications

QtObject {
    id: handler

    // ── Exposed state ──────────────────────────────────────────────────
    property bool   active:   false
    property string summary:  ""
    property string body:     ""
    property string appName:  ""
    property string appIcon:  ""
    property url    image:    ""
    property int    urgency:  0  // 0=Low, 1=Normal, 2=Critical
    property var    actions:  []

    // ── DND (Do Not Disturb) ────────────────────────────────────────────
    property bool dndEnabled: false

    signal notificationArrived()
    signal notificationDismissed()

    // ── Internal queue ─────────────────────────────────────────────────
    property var _queue: []
    property var _currentNotif: null

    property var _notifConnections: Connections {
        target: _currentNotif
        ignoreUnknownSignals: true
        function onSummaryChanged() { if (_currentNotif) handler.summary = _currentNotif.summary; }
        function onBodyChanged()    { if (_currentNotif) handler.body    = _currentNotif.body; }
        function onImageChanged()   { if (_currentNotif) handler.image   = _currentNotif.image; }
        function onAppIconChanged() { if (_currentNotif) handler.appIcon = _currentNotif.appIcon; }
        function onActionsChanged() { if (_currentNotif) handler.actions = _currentNotif.actions; }
    }

    // ── Auto-dismiss timer ─────────────────────────────────────────────
    property var _dismissTimer: Timer {
        interval: 5000
        onTriggered: handler.dismiss()
    }

    // ── Notification Server (shared from shell.qml) ───────────────────
    required property var server

    property var _serverConnections: Connections {
        target: handler.server
        ignoreUnknownSignals: true
        function onNotification(notification) {
            // Skip notifications from previous reload sessions
            if (notification.lastGeneration) return;

            // DND: suppress popup for non-critical notifications
            // The notification is still stored in history by NotifHistoryModel
            if (handler.dndEnabled && (notification.urgency !== 2)) {
                // Track it so history model picks it up, but don't show popup
                notification.tracked = true;
                return;
            }

            handler._queue.push(notification);

            // Immediately show if nothing is active
            if (!handler.active) {
                handler._showNext();
            }
        }
    }

    // ── Show next notification from queue ───────────────────────────────
    function _isNotifValid(notif) {
        // Check if notification object is still alive and usable
        try {
            if (!notif) return false;
            // Try to access a property – if the C++ object was destroyed,
            // this will throw or return undefined in a detectable way
            var test = notif.summary;
            return (test !== undefined);
        } catch(e) {
            return false;
        }
    }

    function _showNext() {
        // Skip any destroyed/invalid notifications in the queue
        while (_queue.length > 0) {
            var candidate = _queue[0];
            if (_isNotifValid(candidate)) break;
            _queue.shift(); // discard invalid entry
        }

        if (_queue.length === 0) {
            active = false;
            _currentNotif = null;
            summary = "";
            body    = "";
            appName = "";
            appIcon = "";
            image   = "";
            urgency = 0;
            actions = [];
            _safetyTimer.stop();
            notificationDismissed();
            return;
        }

        var notif = _queue.shift();
        _currentNotif = notif;

        try {
            summary = notif.summary  || "";
            body    = notif.body     || "";
            appName = notif.appName  || "";
            appIcon = notif.appIcon  || "";
            
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

            image = resolveIcon(notif.image, false) || resolveIcon(notif.appIcon, true) || "";
            
            // Debugging log if no image found for a known app
            if (image === "" && notif.appName !== "") {
                console.log("NotificationHandler: Warning - No icon resolved for app:", notif.appName, 
                            "| appIcon hint:", notif.appIcon, "| image hint:", notif.image);
            }

            urgency = notif.urgency  ?? 1;
            actions = notif.actions  || [];
        } catch(e) {
            console.log("NotificationHandler: notification object became invalid during read, skipping:", e);
            _currentNotif = null;
            _nextTimer.start(); // try the next one
            return;
        }

        active = true;
        notificationArrived();

        // Set auto-dismiss (critical gets longer)
        _dismissTimer.interval = (urgency === 2) ? 8000 : 5000;
        _dismissTimer.restart();

        // Start safety watchdog – if nothing dismisses this in 15s, force-dismiss
        _safetyTimer.restart();
    }

    // ── Dismiss current notification ───────────────────────────────────
    function dismiss() {
        _dismissTimer.stop();
        _safetyTimer.stop();

        if (_currentNotif) {
            try {
                _currentNotif.dismiss();
            } catch(e) {
                console.log("NotificationHandler: dismiss() failed (object already destroyed):", e);
            }
            _currentNotif = null;
        }

        // Short delay before showing next, to let collapse animation play
        _nextTimer.start();
    }

    property var _nextTimer: Timer {
        interval: 600
        onTriggered: handler._showNext()
    }

    // ── Safety watchdog: auto-dismiss if stuck ─────────────────────────
    property var _safetyTimer: Timer {
        interval: 15000
        onTriggered: {
            console.log("NotificationHandler: safety timeout – force dismissing stuck notification");
            handler.dismiss();
        }
    }
}
