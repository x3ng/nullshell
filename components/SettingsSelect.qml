pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic
import ".."

Basic.ComboBox {
    id: picker
    required property Theme style
    implicitHeight: style.fieldHeight
    implicitWidth: 120
    leftPadding: style.spaceMd
    rightPadding: 2 * style.spaceMd
    font.family: style.fontFamily
    font.pixelSize: style.fontSizeBody

    contentItem: Text {
        text: picker.displayText
        font: picker.font
        color: picker.style.textPrimary
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: StatusIcon {
        x: picker.width - width - picker.style.spaceMd
        y: (picker.height - height) / 2
        width: 16
        height: 16
        kind: "chevron-down"
        ink: picker.style.textSecondary
    }
    background: Rectangle {
        radius: picker.style.radiusControl
        color: picker.hovered && picker.enabled ? picker.style.surfaceHover : picker.style.inputSurface
        border.color: picker.activeFocus ? picker.style.focusInk : picker.style.fieldOutline
        border.width: picker.activeFocus ? picker.style.focusWidth : 1
        opacity: picker.enabled ? 1 : 0.55
    }
    delegate: Basic.ItemDelegate {
        id: option
        required property string modelData
        required property int index
        width: picker.width - 8
        implicitHeight: 34
        leftPadding: picker.style.spaceSm
        rightPadding: picker.style.spaceSm
        highlighted: picker.highlightedIndex === index
        contentItem: Text {
            text: option.modelData
            font: picker.font
            color: picker.style.textPrimary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: picker.style.radiusSmall
            color: option.highlighted || option.hovered ? picker.style.surfaceSelected : "transparent"
        }
    }
    popup: Basic.Popup {
        y: picker.height + 4
        width: picker.width
        padding: 4
        implicitHeight: Math.min(240, contentItem.implicitHeight + 8)
        contentItem: ListView {
            clip: true
            spacing: 2
            implicitHeight: contentHeight
            model: picker.delegateModel
            currentIndex: picker.highlightedIndex
        }
        background: Rectangle {
            color: picker.style.surfaceRaised
            border.color: picker.style.outline
            border.width: 1
            radius: picker.style.radiusCard
        }
    }
}
