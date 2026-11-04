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
    signal activateRequested(int index)

    function showSelection(index) { resultList.positionViewAtIndex(index, ListView.Contain); }
    function resetScroll() { resultList.positionViewAtBeginning(); }
    function kindLabel(kind) {
        return kind === "WINDOW" ? "Window" : kind === "APP" ? "Application" : "Command";
    }

    readonly property real naturalHeight: resultHeading.implicitHeight + spacing
        + (page.results.length ? page.results.length * 58
            + Math.max(0, page.results.length - 1) * resultList.spacing : 110)
    Layout.minimumHeight: 0
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 10

    RowLayout {
        id: resultHeading
        spacing: 16
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Text {
            text: page.searchModel.scopeLabel || "Results"
            color: page.style.textMuted
            font.family: page.style.fontFamily
            font.pixelSize: page.style.fontSizeCaption
        }
        Item { Layout.fillWidth: true }
        Text {
            visible: page.width >= 520 && page.searchModel.scope === "ALL"
            text: "> Commands    @ Windows    / Applications"
            color: page.style.textMuted
            font.family: page.style.fontFamily
            font.pixelSize: page.style.fontSizeCaption
        }
        Text {
            text: page.results.length === 1 ? "1 result" : page.results.length + " results"
            color: page.style.textMuted
            font.family: page.style.fontFamily
            font.pixelSize: page.style.fontSizeCaption
        }
    }
    ListView {
        id: resultList
        Layout.minimumHeight: 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: StableRows { rows: page.active ? page.results : [] }
        spacing: 3
        delegate: Rectangle {
            id: resultRow
            required property var record
            readonly property var modelData: record
            required property int index
            width: resultList.width
            height: 58
            opacity: modelData.enabled === false ? 0.45 : 1
            radius: page.style.radiusControl
            color: index === page.selectedIndex ? page.style.surfaceSelected
                : rowMouse.containsMouse ? page.style.surfaceHover : "transparent"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12
                Item {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    IconImage {
                        id: resultIcon
                        anchors.fill: parent
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
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: resultRow.modelData.title
                        textFormat: Text.PlainText
                        color: resultRow.index === page.selectedIndex
                            ? page.style.textSelected : page.style.textPrimary
                        elide: Text.ElideRight
                        font.family: page.style.fontFamily
                        font.pixelSize: page.style.fontSizeBody
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: resultRow.modelData.enabled === false ? "Currently unavailable"
                            : resultRow.modelData.detail || page.kindLabel(resultRow.modelData.kind)
                        textFormat: Text.PlainText
                        color: page.style.textMuted
                        elide: Text.ElideRight
                        font.family: page.style.fontFamily
                        font.pixelSize: page.style.fontSizeCaption
                    }
                }
                Text {
                    text: resultRow.index === page.selectedIndex && resultRow.modelData.enabled !== false
                        ? "↵" : page.kindLabel(resultRow.modelData.kind)
                    color: resultRow.index === page.selectedIndex ? page.style.textSecondary : page.style.textMuted
                    font.family: page.style.fontFamily
                    font.pixelSize: resultRow.index === page.selectedIndex ? 18 : page.style.fontSizeCaption
                    Layout.preferredWidth: 70
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
                    : "Try a different name, or remove the prefix to search everything."
                wrapMode: Text.Wrap
                color: page.style.textMuted
                font.family: page.style.fontFamily
                font.pixelSize: page.style.fontSizeCaption
            }
        }
    }
}
