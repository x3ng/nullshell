import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore
import Quickshell
import Quickshell.Widgets
import "components"

ColumnLayout {
    id: root
    objectName: "wallpaper-picker"
    required property var wallpaper
    required property Theme style
    property bool detached: false
    property string pendingPath: ""
    property bool applied: false
    readonly property bool dialogOpen: fileDialog.visible
    function cancelDialog() { fileDialog.reject(); }
    onPendingPathChanged: applied = false
    readonly property var outputs: ["All displays"].concat(Quickshell.screens.map(screen => screen.name))
    readonly property string outputName: outputChoice.currentIndex > 0 ? outputs[outputChoice.currentIndex] || "" : ""
    spacing: style.spaceMd

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

    RowLayout {
        Layout.fillWidth: true
        spacing: root.style.spaceSm
        Text {
            text: "Display"
            color: root.style.textPrimary
            font.family: root.style.fontFamily
            font.pixelSize: root.style.fontSizeBody
        }
        Item { Layout.fillWidth: true }
        SettingsSelect {
            id: outputChoice
            style: root.style
            Layout.preferredWidth: 170
            Accessible.name: "Display"
            model: root.outputs
            enabled: !root.wallpaper.saving
            onActivated: root.loadSelection()
        }
    }
    ClippingRectangle {
        id: previewFrame
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: root.detached ? Number.POSITIVE_INFINITY : 540
        implicitHeight: width * 9 / 16
        Layout.minimumHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        radius: root.style.radiusCard
        color: root.style.surfaceRaised
        border.width: 1
        border.color: root.style.separator
        WallpaperImage {
            id: preview
            objectName: "wallpaper-preview"
            anchors.fill: parent
            source: root.wallpaper.urlFor(root.pendingPath)
            fit: ["cover", "contain", "stretch"][fitChoice.currentIndex] || "cover"
            fallbackColor: root.style.surfaceRaised
        }
        StatusIcon {
            anchors.centerIn: parent
            width: 24; height: 24
            visible: !preview.hasFrame
            kind: "wallpaper"
            ink: root.style.textMuted
        }
    }
    Text {
        Layout.fillWidth: true
        visible: root.pendingPath !== ""
        text: root.pendingPath.startsWith("file://") ? decodeURIComponent(root.pendingPath.split("/").pop()) : root.pendingPath.split("/").pop()
        elide: Text.ElideMiddle
        color: root.style.textSecondary
        font.family: root.style.fontFamily
        font.pixelSize: root.style.fontSizeSmall
    }
    Text {
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.wallpaper.error || (root.applied ? "Wallpaper applied" : "")
        wrapMode: Text.Wrap
        color: root.wallpaper.error ? root.style.danger : root.style.textSecondary
        font.family: root.style.fontFamily
        font.pixelSize: root.style.fontSizeSmall
    }
    SettingsActions {
        style: root.style
        ChoiceButton {
            objectName: "wallpaper-choose"
            Layout.fillWidth: true
            Layout.preferredWidth: 140
            Layout.preferredHeight: root.style.fieldHeight
            style: root.style
            label: "Choose image…"
            filled: true
            available: !root.wallpaper.saving
            onTriggered: root.chooseImage()
        }
        SettingsSelect { id: fitChoice; style: root.style; Accessible.name: "Image fit"; model: ["Fill", "Fit", "Stretch"]; Layout.preferredWidth: 105; enabled: !root.wallpaper.saving; onActivated: root.applied = false }
        ChoiceButton {
            objectName: "wallpaper-apply"
            Layout.preferredWidth: 80
            Layout.preferredHeight: root.style.fieldHeight
            style: root.style
            tone: "primary"
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
