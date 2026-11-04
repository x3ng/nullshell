pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import ".."

Controls.ToolTip {
    id: tip
    required property Theme style

    // Keep the popup in the shell scene and independent of the platform's
    // toolTipBase/toolTipText palette (often the default yellow/black).
    popupType: Controls.Popup.Item
    delay: style.tooltipDelay
    margins: style.spaceSm
    leftPadding: style.spaceMd
    rightPadding: style.spaceMd
    topPadding: style.spaceSm
    bottomPadding: style.spaceSm
    width: Math.min(implicitWidth, style.maximumTooltipWidth,
        Math.max(1, (Controls.Overlay.overlay?.width ?? (style.maximumTooltipWidth + margins * 2)) - margins * 2))
    x: parent ? (parent.width - width) / 2 : 0
    y: -height - style.spaceSm

    contentItem: Text {
        text: tip.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 8
        elide: Text.ElideRight
        color: tip.style.textPrimary
        font.family: tip.style.fontFamily
        font.pixelSize: tip.style.fontSizeSmall
    }
    background: MaterialSurface {
        materialTheme: tip.style
        color: tip.style.panelSurface
        radius: tip.style.radiusPopup
        border.width: 1
        border.color: tip.style.materialEdge
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: tip.style.motionHintEnter; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: tip.style.motionHintExit }
    }
}
