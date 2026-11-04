pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "components/NotificationUtils.js" as NotificationUtils

// Freedesktop notification daemon (replaces mako). Three lists, matching how
// Noctalia and DankMaterialShell split the same problem:
//   - `popups`  live banners; short-lived and never persisted.
//   - `current` notifications the user has not dealt with yet. The status
//     page card shows these and its Clear empties only this list.
//   - `history` the saved log the detail page browses, kept across restarts.
// Banner timeout only hides the toast. Live objects remain separately bounded
// so the center can still invoke the application's actions after the toast ends.
Scope {
    id: root

    // Live popup wrappers, newest last. Capped; overflow evicts the oldest.
    property var popups: []
    // Runtime objects only; never serialize actions or D-Bus notification IDs.
    property var liveNotifications: []
    // Pending entries, newest first, `time` is epoch ms.
    property var current: []
    // Saved log entries, newest first, `time` is epoch ms.
    property var history: []
    // Live banner stack.
    readonly property int maxVisible: 4
    // Active list shown by the status page card, and how much of it is
    // previewed before the "more" line hands the rest to the detail page.
    readonly property int previewCount: 2
    readonly property int maxCurrent: 20
    // History is re-read on every start, so it has to stay bounded (entry
    // bodies are arbitrary application text).
    readonly property int maxHistory: 50
    // Keep diagnostic tips (e.g. fcitx5's Wayland warnings) available after
    // their banners close. Set false to honor toast-only transient hints.
    property bool recordTransient: true

    // Popup lifetime: app-provided timeout when set, else mako's default
    // of 5s. Critical notifications stay until dismissed.
    readonly property int defaultTimeout: 5000

    readonly property string historyFile: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/nullshell/notifications.json"
    readonly property string legacyHistoryFile: Quickshell.cacheDir + "/notification_history.json"
    property int nextRecord: 0
    // Bulk-clear intent must survive the asynchronous startup snapshot load.
    property bool currentClearedBeforeLoad: false
    property bool historyClearedBeforeLoad: false
    property bool historyLoaded: false
    property var closedLocalKeys: []
    property bool legacyRequested: false
    property bool persistenceAllowed: false
    property string persistenceError: ""
    property bool historyDirty: false
    property int historyRevision: 0
    property int writingRevision: 0
    property bool writeInFlight: false
    property var persistedContents: null
    property string writingContents: ""

    NotificationServer {
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false
        persistenceSupported: true

        onNotification: notif => root.track(notif)
    }

    component NotifWrapper: QtObject {
        id: wrapper
        // Local alerts use the same card lifecycle with an immutable JS payload.
        required property var notification
        property string localKey: ""
        required property string recordKey
        property double time: Date.now()
        readonly property string appName: notification.appName
            || DesktopEntries.heuristicLookup(notification.desktopEntry)?.name || "Application"
        readonly property string summary: notification.summary
        readonly property string body: notification.body
        readonly property string appIcon: notification.appIcon
            || DesktopEntries.heuristicLookup(notification.desktopEntry)?.icon || ""
        readonly property string desktopEntry: notification.desktopEntry || ""
        readonly property string contentImage: notification.image
        readonly property int urgency: notification.urgency
        readonly property bool critical: urgency === NotificationUrgency.Critical
        readonly property var actions: notification.actions
        property bool hovered: false
        property bool closing: false
        property double remaining: timeout
        property double deadline: 0
        readonly property int timeout: {
            if (wrapper.critical) return 0;
            const t = wrapper.notification.expireTimeout;
            return t >= 0 ? t : root.defaultTimeout;
        }
        readonly property Timer timer: Timer {
            interval: Math.max(1, wrapper.remaining)
            onTriggered: root.expire(wrapper)
        }
        function restartTimeout() {
            timer.stop();
            remaining = timeout;
            if (!hovered && timeout > 0) {
                deadline = Date.now() + remaining;
                timer.start();
            }
        }
        // Replaces-id updates modify the same Notification object. Coalesce
        // its property changes so the card and saved record update together.
        readonly property Timer updateTimer: Timer {
            interval: 0
            onTriggered: {
                if (!wrapper.closing) {
                    wrapper.time = Date.now();
                    root.saveRecord(wrapper);
                    wrapper.restartTimeout();
                }
            }
        }
        // Apps may close their own notification (e.g. after a reply);
        // drop the popup so nothing lingers on screen.
        readonly property Connections closedWatch: Connections {
            target: wrapper.localKey ? null : wrapper.notification
            function onClosed() { root.notificationClosed(wrapper); }
            function onSummaryChanged() { wrapper.updateTimer.restart(); }
            function onBodyChanged() { wrapper.updateTimer.restart(); }
            function onAppNameChanged() { wrapper.updateTimer.restart(); }
            function onAppIconChanged() { wrapper.updateTimer.restart(); }
            function onDesktopEntryChanged() { wrapper.updateTimer.restart(); }
            function onImageChanged() { wrapper.updateTimer.restart(); }
            function onUrgencyChanged() { wrapper.updateTimer.restart(); }
            function onActionsChanged() { wrapper.updateTimer.restart(); }
            function onExpireTimeoutChanged() { wrapper.updateTimer.restart(); }
            function onTransientChanged() { wrapper.updateTimer.restart(); }
        }
    }

    function track(notif) {
        notif.tracked = true;
        const existing = liveNotifications.find(w => w.notification === notif);
        if (existing) {
            if (!popups.includes(existing)) popups = [...popups, existing];
            existing.updateTimer.restart();
            limitPopups();
            return;
        }
        const wrapper = notifWrapperComponent.createObject(root, {
            notification: notif,
            recordKey: Date.now() + ":" + (++nextRecord)
        });
        if (!wrapper) return;
        liveNotifications = [...liveNotifications, wrapper];
        saveRecord(wrapper);
        popups = [...popups, wrapper];
        wrapper.restartTimeout();
        limitPopups();
        limitLive();
    }

    function limitPopups() {
        while (popups.length > maxVisible)
            expire(popups.find(w => !w.hovered) || popups[0]);
    }
    function limitLive() {
        while (liveNotifications.length > maxHistory)
            dismiss(liveNotifications.find(w => !popups.includes(w)) || liveNotifications[0]);
    }

    // Stable local keys replace one record instead of growing duplicate alerts.
    // Local payloads deliberately have no application actions or D-Bus lifetime.
    function notifyLocal(key, details) {
        if (!key || !details || !details.summary) return false;
        closedLocalKeys = closedLocalKeys.filter(k => k !== key);
        const payload = {
            appName: details.appName || "System", desktopEntry: "",
            summary: details.summary, body: details.body || "",
            appIcon: details.appIcon || "", image: "", actions: [],
            urgency: details.critical ? NotificationUrgency.Critical : NotificationUrgency.Normal,
            expireTimeout: -1, transient: false, resident: false
        };
        let wrapper = liveNotifications.find(w => w.localKey === key);
        if (wrapper) {
            wrapper.notification = payload;
            wrapper.time = Date.now();
            if (!popups.includes(wrapper)) popups = [...popups, wrapper];
        } else {
            wrapper = notifWrapperComponent.createObject(root, {
                notification: payload, localKey: key, recordKey: "local:" + key
            });
            if (!wrapper) return false;
            liveNotifications = [...liveNotifications, wrapper];
            popups = [...popups, wrapper];
        }
        saveRecord(wrapper);
        wrapper.restartTimeout();
        limitPopups();
        limitLive();
        return true;
    }

    function closeLocal(key) {
        if (!historyLoaded && !closedLocalKeys.includes(key)) {
            closedLocalKeys = [...closedLocalKeys, key];
            persistHistory();
        }
        const wrapper = liveNotifications.find(w => w.localKey === key);
        if (wrapper) remove(wrapper);
        const remaining = current.filter(e => e.recordKey !== "local:" + key);
        if (remaining.length !== current.length) {
            current = remaining;
            persistHistory();
        }
    }

    function saveRecord(wrapper) {
        current = current.filter(e => e.recordKey !== wrapper.recordKey);
        history = history.filter(e => e.recordKey !== wrapper.recordKey);
        // Some apps mark useful warnings as transient, including fcitx5.
        if (recordTransient || !wrapper.notification.transient) {
            const record = {
                recordKey: wrapper.recordKey,
                appName: wrapper.appName,
                summary: wrapper.summary,
                body: wrapper.body,
                appIcon: NotificationUtils.savedImage(wrapper.appIcon),
                desktopEntry: wrapper.desktopEntry || "",
                contentImage: NotificationUtils.savedImage(wrapper.contentImage),
                urgency: wrapper.urgency,
                time: wrapper.time
            };
            // The same record object backs both lists this session, so the
            // detail page and the card never disagree about an entry.
            current = [record, ...current].slice(0, maxCurrent);
            history = [record, ...history].slice(0, maxHistory);
        }
        persistHistory();
    }

    function setHovered(wrapper, hovered) {
        if (wrapper.closing || wrapper.hovered === hovered) return;
        wrapper.hovered = hovered;
        if (hovered) {
            if (wrapper.timer.running) {
                wrapper.timer.stop();
                wrapper.remaining = Math.max(1, wrapper.deadline - Date.now());
            }
        } else if (wrapper.timeout > 0) {
            wrapper.deadline = Date.now() + wrapper.remaining;
            wrapper.timer.start();
        }
    }

    function remove(wrapper) {
        if (wrapper.closing) return;
        wrapper.closing = true;
        wrapper.timer.stop();
        wrapper.updateTimer.stop();
        popups = popups.filter(w => w !== wrapper);
        liveNotifications = liveNotifications.filter(w => w !== wrapper);
        wrapper.destroy();
    }

    function notificationClosed(wrapper) {
        current = current.filter(e => e.recordKey !== wrapper.recordKey);
        remove(wrapper);
        persistHistory();
    }

    // Retain recorded notifications after their banner timeout. Calling expire()
    // on the native object here would invalidate all of its application actions.
    function expire(wrapper) {
        if (wrapper.closing) return;
        wrapper.timer.stop();
        popups = popups.filter(w => w !== wrapper);
        if (!current.some(e => e.recordKey === wrapper.recordKey)
                && !history.some(e => e.recordKey === wrapper.recordKey)) {
            const notification = wrapper.notification;
            const local = wrapper.localKey;
            remove(wrapper);
            if (!local) { try { notification.expire(); } catch (_) {} }
        }
    }

    // Explicit dismiss closes the live notification and clears its pending row;
    // the saved log remains readable.
    function dismiss(wrapper) {
        if (!wrapper || wrapper.closing || !liveNotifications.includes(wrapper)) return false;
        const notification = wrapper.notification;
        const local = wrapper.localKey;
        current = current.filter(e => e.recordKey !== wrapper.recordKey);
        remove(wrapper);
        if (!local) { try { notification.dismiss(); } catch (_) {} }
        persistHistory();
        return true;
    }

    function invokeAction(wrapper, action) {
        if (!wrapper || wrapper.closing || !liveNotifications.includes(wrapper)
                || !Array.from(wrapper.actions).includes(action)) return false;
        // Native invoke() closes non-resident notifications itself. It may emit
        // closed synchronously, so never dereference the wrapper afterwards.
        try { action.invoke(); return true; } catch (_) { return false; }
    }

    function activate(wrapper) {
        if (!wrapper || wrapper.closing || !liveNotifications.includes(wrapper)) return false;
        const action = Array.from(wrapper.actions).find(a => a.identifier === "default");
        return action ? invokeAction(wrapper, action) : false;
    }

    function liveEntry(entry) {
        return liveNotifications.find(w => !w.closing && w.recordKey === entry?.recordKey) || null;
    }
    function entryActions(entry) {
        return Array.from(liveEntry(entry)?.actions || []);
    }
    function entryApplication(entry) {
        return entry?.desktopEntry ? DesktopEntries.heuristicLookup(entry.desktopEntry) : null;
    }
    function activationLabel(entry) {
        if (entryActions(entry).some(a => a.identifier === "default")) return "Open notification";
        return entryApplication(entry) ? "Open app" : "";
    }
    function activateEntry(entry) {
        const wrapper = liveEntry(entry);
        if (wrapper && entryActions(entry).some(a => a.identifier === "default")) return activate(wrapper);
        const application = entryApplication(entry);
        if (!application) return false;
        try { application.execute(); return true; } catch (_) { return false; }
    }
    function invokeEntryAction(entry, action) {
        return invokeAction(liveEntry(entry), action);
    }

    // Clear the visible pending list in the notification center; keep history.
    function clearCurrent() {
        if (current.length === 0 && historyLoaded) return;
        if (!historyLoaded) currentClearedBeforeLoad = true;
        const keys = new Set(current.map(e => e.recordKey));
        for (const wrapper of liveNotifications.slice()) {
            if (keys.has(wrapper.recordKey)) dismiss(wrapper);
        }
        current = [];
        persistHistory();
    }

    function removeCurrent(index) {
        const entry = current[index];
        if (!entry) return;
        const wrapper = liveEntry(entry);
        if (wrapper) dismiss(wrapper);
        current = current.filter(e => e.recordKey !== entry.recordKey);
        persistHistory();
    }

    function clearHistory() {
        if (history.length === 0 && historyLoaded) return;
        if (!historyLoaded) {
            historyClearedBeforeLoad = true;
            currentClearedBeforeLoad = true;
        }
        const keys = new Set(history.map(e => e.recordKey));
        for (const wrapper of liveNotifications.slice()) {
            if (keys.has(wrapper.recordKey)) dismiss(wrapper);
        }
        current = current.filter(e => !keys.has(e.recordKey));
        history = [];
        persistHistory();
    }

    function removeHistory(index) {
        const entry = history[index];
        if (!entry) return;
        const wrapper = liveEntry(entry);
        if (wrapper) dismiss(wrapper);
        current = current.filter(e => e.recordKey !== entry.recordKey);
        history = history.filter(e => e.recordKey !== entry.recordKey);
        persistHistory();
    }

    // Disk-backed state: like mako's max-history, but it survives quickshell
    // restarts. Writes are debounced to avoid churn.
    function persistHistory() {
        historyDirty = true;
        historyRevision++;
        saveTimer.restart();
    }

    function loadHistory(data) {
        const loadedHistory = (historyClearedBeforeLoad ? [] : data.notifications)
            .filter(e => e && Number.isFinite(e.time));
        const loadedCurrent = (currentClearedBeforeLoad ? [] : (data.current || []))
            .filter(e => e && Number.isFinite(e.time)
                && !closedLocalKeys.some(key => e.recordKey === "local:" + key));
        // Anything that arrived before the async load sits in front.
        const historyKeys = new Set(history.map(e => e.recordKey));
        const currentKeys = new Set(current.map(e => e.recordKey));
        history = [...history, ...loadedHistory.filter(e => !historyKeys.has(e.recordKey))].slice(0, maxHistory);
        current = [...current, ...loadedCurrent.filter(e => !currentKeys.has(e.recordKey))].slice(0, maxCurrent);
        closedLocalKeys = [];
        currentClearedBeforeLoad = false;
        historyClearedBeforeLoad = false;
    }

    function finishLoad(writable, message) {
        if (historyLoaded) return;
        persistenceAllowed = writable;
        persistenceError = message;
        historyLoaded = true;
        if (message) console.warn("Notification history:", message);
        if (historyDirty) saveTimer.restart();
    }

    function applyLoaded(contents, legacy) {
        if (historyLoaded || legacy !== legacyRequested) return;
        let data;
        try {
            data = JSON.parse(contents);
        } catch (_) {
            finishLoad(false, "Invalid JSON; preserving the original history file.");
            return;
        }
        if (!data || !Array.isArray(data.notifications)
                || (data.current !== undefined && !Array.isArray(data.current))
                || (data.version !== undefined && data.version !== 1)) {
            finishLoad(false, "Unsupported history format; preserving the original file.");
            return;
        }
        loadHistory(data);
        if (!legacy) persistedContents = contents;
        if (legacy) persistHistory();
        finishLoad(true, "");
    }

    function loadFailed(error, legacy) {
        if (historyLoaded || legacy !== legacyRequested) return;
        if (error !== FileViewError.FileNotFound) {
            finishLoad(false, "Could not read history; preserving the original file.");
        } else if (!legacy) {
            // Only absence permits migration. Existing empty/corrupt state is
            // never replaced by stale cache contents.
            legacyRequested = true;
        } else {
            persistHistory();
            finishLoad(true, "");
        }
    }

    function flushHistory() {
        if (!historyLoaded || !persistenceAllowed || !historyDirty || writeInFlight) return;
        const contents = JSON.stringify({version: 1, notifications: history, current: current}) + "\n";
        // FileView skips same-content writes without emitting saved.
        if (contents === persistedContents) {
            historyDirty = false;
            return;
        }
        writingRevision = historyRevision;
        writingContents = contents;
        writeInFlight = true;
        historyFileView.setText(contents);
    }

    function historySaved() {
        if (!writeInFlight) return;
        writeInFlight = false;
        persistedContents = writingContents;
        persistenceError = "";
        historyDirty = historyRevision !== writingRevision;
        if (historyDirty) saveTimer.restart();
    }

    function historySaveFailed() {
        writeInFlight = false;
        persistenceAllowed = false;
        persistenceError = "Could not save notification history; further changes remain in memory this session.";
        console.warn(persistenceError);
        // FileView caches failed text too, so a same-content retry would never
        // emit saved. Preserve disk data and retry loading on the next startup.
    }

    Timer {
        id: saveTimer
        interval: 200
        onTriggered: root.flushHistory()
    }

    FileView {
        id: historyFileView
        path: root.historyFile
        preload: true
        blockLoading: false
        blockWrites: false
        atomicWrites: true
        watchChanges: false
        printErrors: false
        onLoaded: root.applyLoaded(text(), false)
        onLoadFailed: error => root.loadFailed(error, false)
        onSaved: root.historySaved()
        onSaveFailed: root.historySaveFailed()
    }

    FileView {
        id: legacyFileView
        path: root.legacyRequested ? root.legacyHistoryFile : ""
        preload: root.legacyRequested
        blockLoading: false
        watchChanges: false
        printErrors: false
        onLoaded: { if (root.legacyRequested) root.applyLoaded(text(), true); }
        onLoadFailed: error => { if (root.legacyRequested) root.loadFailed(error, true); }
    }

    Component {
        id: notifWrapperComponent
        NotifWrapper {}
    }
}
