.pragma library

// Normalize Quickshell notification image/icon strings into safe Qt URLs.
// Quickshell's Notification.image wraps absolute file paths from image-path
// hints as "image://icon//abs/path"; passing a path to QIcon::fromTheme fails
// and returns Quickshell's black-magenta missing-texture checkerboard with
// Image.Ready. Unwrap file paths to file:// so Qt decodes existing files and
// reports Image.Error (hidden cleanly) when temp files are later deleted.
function normalizePathOrUrl(value) {
    var source = String(value || "").trim();
    if (!source) return "";
    if (source.startsWith("image://icon//")) {
        var path = source.slice("image://icon/".length);
        var query = path.indexOf("?");
        if (query >= 0) path = path.slice(0, query);
        return "file://" + path;
    }
    if (source.startsWith("/")) return "file://" + source;
    return source;
}

function imageSource(value, resolveIcon) {
    var source = normalizePathOrUrl(value);
    if (!source) return "";
    if (source.startsWith("file://") || source.startsWith("image://qsimage/")) return source;
    var iconName = source;
    if (source.startsWith("image://icon/")) {
        iconName = source.slice("image://icon/".length);
        var query = iconName.indexOf("?");
        if (query >= 0) iconName = iconName.slice(0, query);
        if (iconName.startsWith("/")) return "file://" + iconName;
    } else if (/^[a-z][a-z0-9+.-]*:/i.test(source)) {
        return source;
    }
    if (!iconName) return "";
    if (typeof resolveIcon === "function") return resolveIcon(iconName) || "";
    return "image://icon/" + iconName;
}

function attachmentSource(value) {
    var source = normalizePathOrUrl(value);
    if (source.startsWith("file://") || source.startsWith("image://qsimage/")) return source;
    return "";
}

function savedImage(value) {
    var source = normalizePathOrUrl(value);
    // qsimage belongs to a live Notification, not a disk-backed record.
    return source.startsWith("image://qsimage/") ? "" : source;
}

function timestamp(value) {
    var date = new Date(value);
    return date.toDateString() === new Date().toDateString()
        ? Qt.formatTime(date, "hh:mm")
        : Qt.formatDateTime(date, "MM-dd hh:mm");
}
