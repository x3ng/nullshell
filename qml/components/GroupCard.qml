pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

// One labelled surface per related set of controls; avoid nested cards.
Rectangle {
    id: card
    required property Theme style
    default property alias content: body.data
    property string title: ""
    property string iconKind: ""
    property int pad: card.style.spaceMd
    property real contentSpacing: style.spaceSm
    // Emitted when the card body is tapped; per-control MouseAreas
    // declared inside take precedence over this.
    signal activated()

    color: card.style.surfaceRaised
    border.width: 0
    border.color: card.style.separator
    radius: card.style.radiusCard
    implicitWidth: inner.implicitWidth + card.pad * 2
    implicitHeight: inner.implicitHeight + card.pad * 2

    MouseArea {
        anchors.fill: parent
        onClicked: card.activated()
    }

    ColumnLayout {
        id: inner
        x: card.pad
        y: card.pad
        width: card.width - card.pad * 2
        spacing: card.contentSpacing
        RowLayout {
            Layout.fillWidth: true
            visible: card.title !== ""
            spacing: card.style.spaceSm
            StatusIcon {
                visible: card.iconKind !== ""
                kind: card.iconKind
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                ink: card.style.textSecondary
            }
            Text {
                Layout.fillWidth: true
                text: card.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: card.style.textPrimary
                font.family: card.style.fontFamily
                font.pixelSize: card.style.fontSizeSmall
                font.weight: Font.DemiBold
            }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: card.contentSpacing
        }
    }
}
