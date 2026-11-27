pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: banner
    required property Theme style
    required property string title
    property string detail: ""
    property string iconKind: ""
    property color ink: style.accent
    // "neutral" is informational and borderless; "warning" outlines in the ink colour.
    property string tone: "neutral"
    property alias actions: actionRow.data

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 2 * style.spaceMd
    color: style.surfaceRaised
    radius: style.radiusCard
    border.color: Qt.rgba(ink.r, ink.g, ink.b, 0.5)
    border.width: tone === "neutral" ? 0 : 1

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: banner.style.spaceMd
        spacing: banner.style.spaceMd
        StatusIcon {
            visible: banner.iconKind !== ""
            kind: banner.iconKind
            ink: banner.ink
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: banner.style.spaceXs
            Text {
                Layout.fillWidth: true
                text: banner.title
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: banner.style.textPrimary
                font.family: banner.style.fontFamily
                font.pixelSize: banner.style.fontSizeBody
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                visible: banner.detail !== ""
                text: banner.detail
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: banner.style.textSecondary
                font.family: banner.style.fontFamily
                font.pixelSize: banner.style.fontSizeSmall
            }
        }
        RowLayout { id: actionRow; spacing: banner.style.spaceXs; visible: children.length > 0 }
    }
}
