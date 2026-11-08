.pragma library

// Preserve provider URLs, file URLs and absolute paths. Only bare icon names
// belong in the icon provider.
function imageSource(value) {
    const source = String(value || "");
    if (!source) return "";
    if (/^[a-z][a-z0-9+.-]*:/i.test(source)) return source;
    if (source.startsWith("/")) return "file://" + source;
    return "image://icon/" + source;
}

function savedImage(value) {
    const source = String(value || "");
    // qsimage belongs to a live Notification, not a disk-backed record.
    return source.startsWith("image://qsimage/") ? "" : source;
}

function timestamp(value) {
    const date = new Date(value);
    return date.toDateString() === new Date().toDateString()
        ? Qt.formatTime(date, "hh:mm")
        : Qt.formatDateTime(date, "MM-dd hh:mm");
}
