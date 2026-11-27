pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import ".."

// Search presentation only. Navigation and activation remain in LauncherPanel.
ColumnLayout {
    id: page
    required property Theme style
    required property var results
    required property var searchModel
    required property int selectedIndex
    required property bool active
    property bool commandScope: false
    signal activateRequested(int index)

    function showSelection(index) { resultList.positionViewAtIndex(index, ListView.Contain); }
    function resetScroll() { resultList.positionViewAtBeginning(); }
    function kindLabel(row) {
        return row.kind === "WINDOW" ? "Window" : row.kind === "APP" ? "Application"
            : row.actionType === "panel" ? "Panel" : "Action";
    }
    function actionHint(row) {
        if (row.enabled === false) return "Unavailable";
        return row.kind !== "ACTION" || row.actionType === "panel" ? "↵ Open →" : "↵ Run";
    }

    readonly property real naturalHeight: resultHeading.implicitHeight + spacing
        + (page.results.length ? page.results.length * 60
            + Math.max(0, page.results.length - 1) * resultList.spacing : 110)
    Layout.minimumHeight: 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: page.style.spaceMd

    RowLayout {
        id: resultHeading
        spacing: 16
        Layout.fillWidth: true
        Layout.leftMargin: page.style.spaceSm
        Layout.rightMargin: page.style.spaceSm
        Text {
            text: page.searchModel.scopeLabel || "Results"
            color: page.style.textMuted
            font.family: page.style.fontFamily
            font.pixelSize: page.style.fontSizeLabel
            font.weight: Font.Medium
        }
        Item { Layout.fillWidth: true }
        Text {
            text: page.results.length === 1 ? "1 result" : page.results.length + " results"
            color: page.style.textMuted
            font.family: page.style.fontFamily
            font.pixelSize: page.style.fontSizeLabel
        }
    }
    ListView {
        id: resultList
        Layout.minimumHeight: 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: StableRows { rows: page.active ? page.results : [] }
        spacing: page.style.spaceXs
        delegate: Rectangle {
            id: resultRow
            required property var record
            readonly property var modelData: record
            required property int index
            width: resultList.width
            height: 60
            // Unavailable rows keep a readable reason; only the icon is dimmed.
            readonly property bool unavailable: modelData.enabled === false
            radius: page.style.radiusControl
            color: index === page.selectedIndex ? (rowMouse.containsMouse ? page.style.surfaceSelectedHover : page.style.surfaceSelected)
                : rowMouse.containsMouse ? page.style.surfaceHover : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 0
                anchors.rightMargin: page.style.spaceMd
                spacing: 12
                Item {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 30
                    opacity: resultRow.unavailable ? 0.45 : 1
                    IconImage {
                        id: resultIcon
                        anchors.centerIn: parent
                        width: 30; height: 30
                        implicitSize: 30
                        source: page.searchModel.desktopIconSource(resultRow.modelData.entry)
                        visible: status === Image.Ready
                    }
                    StatusIcon {
                        anchors.centerIn: parent
                        visible: !resultIcon.visible
                        kind: resultRow.modelData.kind === "ACTION" ? resultRow.modelData.icon
                            : resultRow.modelData.kind === "WINDOW" ? "window" : "app"
                        width: 22
                        height: 22
                        ink: page.style.textSecondary
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: page.style.spaceXs
                    Text {
                        Layout.fillWidth: true
                        text: resultRow.modelData.title
                        textFormat: Text.PlainText
                        color: resultRow.unavailable ? page.style.textDisabled
                            : resultRow.index === page.selectedIndex ? page.style.textSelected : page.style.textPrimary
                        elide: Text.ElideRight
                        font.family: page.style.fontFamily
                        font.pixelSize: page.style.fontSizeBody
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: resultRow.unavailable ? "Currently unavailable"
                            : resultRow.modelData.detail || page.kindLabel(resultRow.modelData)
                        textFormat: Text.PlainText
                        color: resultRow.unavailable ? page.style.textDisabled : page.style.textMuted
                        elide: Text.ElideRight
                        font.family: page.style.fontFamily
                        font.pixelSize: page.style.fontSizeLabel
                    }
                }
                Text {
                    text: resultRow.index === page.selectedIndex
                        ? page.actionHint(resultRow.modelData) : page.kindLabel(resultRow.modelData)
                    color: resultRow.index === page.selectedIndex ? page.style.textSecondary : page.style.textMuted
                    font.family: page.style.fontFamily
                    font.pixelSize: page.style.fontSizeLabel
                    Layout.preferredWidth: 84
                    horizontalAlignment: Text.AlignRight
                }
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: resultRow.modelData.enabled !== false
                onClicked: page.activateRequested(resultRow.index)
            }
        }
        Column {
            anchors.centerIn: parent
            width: parent.width - 24
            visible: !page.results.length
            spacing: 8
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.searchModel.scope === "ALL" ? "No results" : "No matching " + page.searchModel.scopeLabel.toLowerCase()
                color: page.style.textPrimary
                font.family: page.style.fontFamily
                font.pixelSize: page.style.fontSizeBody
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.searchModel.scope === "ALL"
                    ? "Try an app name, window title or command. Use >, @ or / to narrow the search."
                    : page.commandScope ? "Try another keyword, or use > to include panels and actions."
                    : "Try a different name, or remove the prefix to search everything."
                wrapMode: Text.Wrap
                color: page.style.textMuted
                font.family: page.style.fontFamily
                font.pixelSize: page.style.fontSizeLabel
            }
        }
    }
}
