pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

MaterialSurface {
    id: card
    materialTheme: style
    required property Theme style
    property string label: ""
    property string icon: "volume"
    property string value: ""
    property bool caution: false
    property bool showProgress: false
    property real progress: 0
    property bool customContent: false
    default property alias content: customSlot.data

    implicitWidth: 320
    implicitHeight: body.implicitHeight + 2 * style.spaceMd
    radius: style.radiusPopup
    color: style.surface
    border.color: style.materialEdge
    border.width: 1
    Accessible.name: label + " " + value

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.style.spaceLg
        anchors.rightMargin: card.style.spaceLg
        anchors.topMargin: card.style.spaceMd

        RowLayout {
            visible: !card.customContent
            width: parent.width
            height: 26
            spacing: 12
            StatusIcon {
                kind: card.icon
                muted: card.caution
                ink: card.caution ? card.style.accentWarm : card.style.textSecondary
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
            }
            Rectangle {
                id: track
                visible: card.showProgress
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                radius: 3
                color: card.style.separator
                Rectangle {
                    width: track.width * Math.max(0, Math.min(1, card.progress))
                    height: parent.height
                    radius: parent.radius
                    color: card.caution ? card.style.accentWarm : card.style.accent
                    Behavior on width {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                }
            }
            Text {
                Layout.fillWidth: !card.showProgress
                Layout.preferredWidth: card.showProgress ? 48 : -1
                text: card.value
                textFormat: Text.PlainText
                elide: Text.ElideRight
                horizontalAlignment: card.showProgress ? Text.AlignRight : Text.AlignLeft
                color: card.caution ? card.style.accentWarm : card.style.textPrimary
                font.family: card.style.fontFamily
                font.pixelSize: card.style.fontSizeBody
                font.weight: Font.Medium
            }
        }
        Item {
            id: customSlot
            visible: card.customContent
            width: parent.width
            height: childrenRect.height
        }
    }
}
