// Connection observations are separate from user intent. No notifications on discovery.
// Stable links arm after 3 seconds; a 4-second grace period absorbs reconnects.
// A request is consumed once, so repeated native failures cannot create duplicates.
function create() { return { entries: {}, pending: false }; }
function request(tracker, key, now) {
    const entry = tracker.entries[key];
    if (!entry) return;
    // Only other connections on this Wi-Fi device belong to this switch.
    if (entry.kind === "wifi") {
        for (const otherKey of Object.keys(tracker.entries)) {
            const other = tracker.entries[otherKey];
            if (otherKey === key || other.kind !== "wifi" || other.device !== entry.device) continue;
            if (other.requested !== null) {
                releaseSwitch(tracker, otherKey);
                other.requested = null;
            }
            if (!other.connected) continue;
            suppress(other, now + 45000, key);
        }
    }
    entry.requested = now;
    entry.sawConnecting = false;
    entry.failure = "";
    entry.failedSince = null;
    entry.suppressedUntil = null;
    entry.suppressedBy = "";
    entry.wasStable = false;
    entry.loss = null;
}
function suppress(entry, until, requestKey) {
    if (entry.suppressedUntil === null) entry.wasStable = entry.stable;
    entry.suppressedUntil = until;
    entry.suppressedBy = requestKey;
    entry.stable = false;
    entry.loss = null;
}
function restore(entry) {
    entry.suppressedUntil = null;
    entry.suppressedBy = "";
    entry.stable = entry.wasStable && entry.connected;
    entry.wasStable = false;
    entry.loss = null;
}
function releaseSwitch(tracker, key) {
    for (const entry of Object.values(tracker.entries))
        if (entry.suppressedBy === key) restore(entry);
}
function silence(tracker, prefix, exact, now) {
    for (const key of Object.keys(tracker.entries)) {
        if (exact ? key !== prefix : !key.startsWith(prefix)) continue;
        const entry = tracker.entries[key];
        releaseSwitch(tracker, key);
        entry.requested = null;
        suppress(entry, (now === undefined ? Date.now() : now) + 5000, "");
    }
}
function failure(tracker, key, reason) {
    const entry = tracker.entries[key];
    if (entry) entry.failure = reason;
}
function observe(tracker, rows, now) {
    const events = [];
    const seen = {};
    tracker.pending = false;
    for (const row of rows) seen[row.key] = row;
    for (const row of rows) {
        if (!tracker.entries[row.key]) {
            tracker.entries[row.key] = {
                name: row.name, kind: row.kind, device: row.device, connected: row.connected, since: null, stable: false,
                loss: null, requested: null, sawConnecting: false, failure: "", failedSince: null, lastFailure: "", lastFailureAt: null, suppressedUntil: null, suppressedBy: "", wasStable: false
            };
        }
    }
    // Update all observations before resolving a switch; ordering must not affect restoration.
    for (const key of Object.keys(tracker.entries)) {
        const entry = tracker.entries[key];
        entry.connected = !!seen[key]?.connected;
        if (!entry.connected) entry.wasStable = false;
    }
    for (const key of Object.keys(tracker.entries)) {
        const entry = tracker.entries[key];
        const row = seen[key];
        const connected = !!row?.connected;
        if (row) entry.name = row.name;
        if (entry.suppressedUntil !== null && now >= entry.suppressedUntil) restore(entry);
        if (entry.requested !== null) {
            if (row?.connecting) entry.sawConnecting = true;
            if (entry.sawConnecting && row && !row.connecting && !connected) {
                if (entry.failedSince === null) entry.failedSince = now;
            } else entry.failedSince = null;
            const failed = entry.failedSince !== null && now - entry.failedSince >= 1000;
            const timedOut = now - entry.requested >= (entry.kind === "wifi" ? 45000 : 25000);
            if (connected) {
                events.push({ key: key, kind: entry.kind, result: "connected", name: entry.name });
                entry.requested = null;
                releaseSwitch(tracker, key);
                entry.failure = "";
            } else if (entry.failure || timedOut || failed) {
                events.push({ key: key, kind: entry.kind, result: "failed", name: entry.name,
                    reason: entry.failure || (timedOut ? "Connection timed out." : "Could not establish a connection.") });
                entry.requested = null;
                releaseSwitch(tracker, key);
                entry.lastFailure = entry.failure;
                entry.lastFailureAt = now;
                entry.failure = "";
                entry.stable = false;
                entry.since = null;
                entry.loss = null;
            } else tracker.pending = true;
        } else if (entry.failure) {
            // Native failures also cover attempts made through another network UI.
            // The same backend reason may repeat while NetworkManager retries.
            if (entry.suppressedUntil === null && (entry.lastFailureAt === null
                    || (now - entry.lastFailureAt >= 2000
                        && (entry.failure !== entry.lastFailure || now - entry.lastFailureAt >= 30000)))) {
                events.push({ key: key, kind: entry.kind, result: "failed", name: entry.name, reason: entry.failure });
                entry.lastFailure = entry.failure;
                entry.lastFailureAt = now;
                entry.stable = false;
                entry.loss = null;
            }
            entry.failure = "";
        }
        // Suppression always has a deadline, including failed radio/disconnect requests.
        if (entry.suppressedUntil !== null) {
            tracker.pending = true;
            continue;
        }
        if (connected) {
            entry.loss = null;
            if (entry.since === null) entry.since = now;
            if (now - entry.since >= 3000) entry.stable = true;
            else tracker.pending = true;
        } else {
            entry.since = null;
            if (entry.stable) {
                if (entry.loss === null) entry.loss = now;
                if (now - entry.loss >= 4000) {
                    events.push({ key: key, kind: entry.kind, result: "lost", name: entry.name });
                    entry.stable = false;
                    entry.loss = null;
                } else tracker.pending = true;
            }
        }
        if (!row && !entry.stable && entry.requested === null) delete tracker.entries[key];
    }
    return events;
}
