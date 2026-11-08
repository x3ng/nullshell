import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell

Window {
    id: root
    required property var wallpaper
    required property var style
    property string pendingPath: ""
    readonly property var outputs: ["All displays"].concat(Quickshell.screens.map(screen => screen.name))
    readonly property string outputName: outputChoice.currentIndex > 0 ? outputs[outputChoice.currentIndex] || "" : ""
    width: 580
    height: 490
    minimumWidth: 420
    minimumHeight: 440
    title: "Wallpaper"
    color: style.panelSurface
    visible: false
    MaterialSurface { anchors.fill: parent; materialTheme: root.style; radius: 0 }

    function loadSelection() {
        const entry = wallpaper.entryFor(outputName);
        pendingPath = entry.path;
        fitChoice.currentIndex = Math.max(0, ["cover", "contain", "stretch"].indexOf(entry.fit));
    }
    function showPicker() {
        loadSelection();
        show();
        raise();
        requestActivate();
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
    component Action: Button {
        implicitHeight: 40
        font.family: root.style.fontFamily
        font.pixelSize: 14
        palette.buttonText: root.style.textPrimary
        background: Rectangle {
            radius: root.style.radiusControl
            color: parent.down || parent.hovered ? root.style.surfaceHover : root.style.surfaceRaised
            opacity: parent.enabled ? 1 : 0.45
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Wallpaper"
                color: root.style.textPrimary
                font.family: root.style.fontFamily
                font.pixelSize: 24
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
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 180
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
            text: root.wallpaper.error
            wrapMode: Text.Wrap
            color: root.style.danger
            font.family: root.style.fontFamily
            font.pixelSize: 13
        }
        RowLayout {
            Layout.fillWidth: true
            Action { text: "Choose image…"; enabled: !root.wallpaper.saving; onClicked: fileDialog.open() }
            Choice { id: fitChoice; model: ["Fill", "Fit", "Stretch"]; Layout.preferredWidth: 105 }
            Item { Layout.fillWidth: true }
            Action {
                text: root.wallpaper.saving ? "Saving…" : "Apply"
                enabled: preview.ready && root.wallpaper.loaded && !root.wallpaper.saving
                onClicked: root.wallpaper.apply(root.outputName, root.pendingPath, preview.fit)
            }
        }
    }
    Connections { target: root.wallpaper; function onSaved() { root.close(); } }
    FileDialog {
        id: fileDialog
        title: "Choose wallpaper"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"]
        currentFolder: "file://" + Quickshell.env("HOME") + "/Pictures"
        onAccepted: root.pendingPath = selectedFile.toString()
    }
}
