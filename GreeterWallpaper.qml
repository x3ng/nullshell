import QtQuick
import Quickshell
import Quickshell.Io

WallpaperImage {
    id: root
    property string snapshotPath: Quickshell.env("NULLSHELL_WALLPAPER_FILE")
    property var snapshot: null
    property string error: ""
    source: {
        if (!snapshot || !snapshot.image) return "";
        const folder = snapshotPath.slice(0, snapshotPath.lastIndexOf("/") + 1);
        return "file://" + (folder + snapshot.image).split("/").map(encodeURIComponent).join("/") + "?revision=" + snapshot.revision;
    }
    fit: snapshot ? snapshot.fit : "cover"
    cacheImage: false
    FileView {
        path: root.snapshotPath
        blockLoading: true
        watchChanges: root.snapshotPath !== ""
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                if (text().length > 8192) throw new Error("Wallpaper descriptor too large");
                const value = JSON.parse(text());
                if (!value || value.version !== 1
                        || Object.keys(value).sort().join(",") !== "fit,image,revision,version"
                        || ![null, "wallpaper-0.img", "wallpaper-1.img"].includes(value.image)
                        || typeof value.revision !== "string"
                        || (value.image ? !/^[0-9a-f]{1,32}-[0-9a-f]{1,8}$/.test(value.revision) : value.revision !== "")
                        || !["cover", "contain", "stretch"].includes(value.fit))
                    throw new Error("Invalid wallpaper descriptor");
                root.snapshot = value;
                root.error = "";
            } catch (e) { root.error = String(e); }
        }
        onLoadFailed: failure => {
            if (root.snapshotPath && failure !== FileViewError.FileNotFound)
                root.error = "Could not read wallpaper descriptor";
        }
    }
}
