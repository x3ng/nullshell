import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Quickshell
import "components"

ColumnLayout {
    id: root
    objectName: "wallpaper-picker"
    required property var wallpaper
    required property var style
    property string pendingPath: ""
    property bool applied: false
    readonly property bool dialogOpen: fileDialog.visible
    function cancelDialog() { fileDialog.reject(); }
    onPendingPathChanged: applied = false
    readonly property var outputs: ["All displays"].concat(Quickshell.screens.map(screen => screen.name))
    readonly property string outputName: outputChoice.currentIndex > 0 ? outputs[outputChoice.currentIndex] || "" : ""
    spacing: 12

    function loadSelection() {
        applied = false;
        const entry = wallpaper.entryFor(outputName);
        pendingPath = entry.path;
        fitChoice.currentIndex = Math.max(0, ["cover", "contain", "stretch"].indexOf(entry.fit));
    }
    Component.onCompleted: loadSelection()
    function chooseImage() {
        const selected = pendingPath ? wallpaper.urlFor(pendingPath).toString() : "";
        if (selected.startsWith("file://")) {
            fileDialog.currentFolder = selected.slice(0, selected.lastIndexOf("/") + 1);
            fileDialog.selectedFile = selected;
        }
        fileDialog.open();
    }

    component Choice: ComboBox {
        implicitHeight: 40
        font.family: root.style.fontFamily
        font.pixelSize: 14
        palette.text: root.style.textPrimary
        palette.buttonText: root.style.textPrimary
        palette.base: root.style.surfaceRaised
        palette.button: root.style.surfaceRaised
        palette.window: root.style.surfaceRaised
        palette.highlight: root.style.surfaceSelected
        palette.highlightedText: root.style.textPrimary
        background: Rectangle { color: root.style.surfaceRaised; radius: root.style.radiusControl }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: root.style.spaceSm
        Text {
            text: "Display"
            color: root.style.textPrimary
            font.family: root.style.fontFamily
            font.pixelSize: 14
        }
        Item { Layout.fillWidth: true }
        Choice {
            id: outputChoice
            Layout.preferredWidth: 170
            model: root.outputs
            enabled: !root.wallpaper.saving
            onActivated: root.loadSelection()
        }
    }
    WallpaperImage {
        id: preview
        objectName: "wallpaper-preview"
        Layout.fillWidth: true
        implicitHeight: width * 9 / 16
        Layout.minimumHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        source: root.wallpaper.urlFor(root.pendingPath)
        fit: ["cover", "contain", "stretch"][fitChoice.currentIndex] || "cover"
        fallbackColor: root.style.surfaceRaised
    }
    Text {
        Layout.fillWidth: true
        text: root.pendingPath ? (root.pendingPath.startsWith("file://") ? decodeURIComponent(root.pendingPath.split("/").pop()) : root.pendingPath.split("/").pop()) : "Choose an image"
        elide: Text.ElideMiddle
        color: root.style.textSecondary
        font.family: root.style.fontFamily
        font.pixelSize: 13
    }
    Text {
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.wallpaper.error || (root.applied ? "Wallpaper applied" : "")
        wrapMode: Text.Wrap
        color: root.wallpaper.error ? root.style.danger : root.style.textSecondary
        font.family: root.style.fontFamily
        font.pixelSize: 13
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: root.style.spaceSm
        ChoiceButton {
            objectName: "wallpaper-choose"
            Layout.fillWidth: true
            Layout.preferredWidth: 140
            Layout.preferredHeight: 40
            style: root.style
            label: "Choose image…"
            filled: true
            available: !root.wallpaper.saving
            onTriggered: root.chooseImage()
        }
        Choice { id: fitChoice; model: ["Fill", "Fit", "Stretch"]; Layout.preferredWidth: 105; enabled: !root.wallpaper.saving; onActivated: root.applied = false }
        ChoiceButton {
            objectName: "wallpaper-apply"
            Layout.preferredWidth: 80
            Layout.preferredHeight: 40
            style: root.style
            filled: true
            label: root.wallpaper.saving ? "Saving…" : "Apply"
            available: preview.ready && root.wallpaper.loaded && !root.wallpaper.saving
            onTriggered: { root.applied = false; root.wallpaper.apply(root.outputName, root.pendingPath, preview.fit); }
        }
    }
    Connections { target: root.wallpaper; function onSaved() { root.applied = true; } }
    FileDialog {
        id: fileDialog
        title: "Choose wallpaper"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: root.pendingPath = selectedFile.toString()
    }
}
