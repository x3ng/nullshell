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
    indicator: Text {
        x: picker.width - width - picker.style.spaceMd
        y: (picker.height - height) / 2
        text: "▾"
        color: picker.style.textSecondary
        font.pixelSize: picker.style.fontSizeSmall
    }
    background: Rectangle {
        radius: picker.style.radiusControl
        color: picker.style.inputSurface
        border.color: picker.activeFocus ? picker.style.focusInk : picker.style.fieldOutline
        border.width: 1
        opacity: picker.enabled ? 1 : 0.55
    }
    delegate: Basic.ItemDelegate {
        id: option
        required property string modelData
        required property int index
        width: picker.width - 2
        highlighted: picker.highlightedIndex === index
        contentItem: Text {
            text: option.modelData
            font: picker.font
            color: picker.style.textPrimary
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: option.highlighted || option.hovered ? picker.style.surfaceSelected : picker.style.panelSurface
        }
    }
    popup: Basic.Popup {
        y: picker.height
        width: picker.width
        padding: 1
        implicitHeight: Math.min(240, contentItem.implicitHeight + 2)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: picker.delegateModel
            currentIndex: picker.highlightedIndex
        }
        background: Rectangle {
            color: picker.style.panelSurface
            border.color: picker.style.separator
            border.width: 1
            radius: picker.style.radiusControl
        }
    }
}
