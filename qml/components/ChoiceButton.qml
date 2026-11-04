pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

Rectangle {
    id: choice

    required property Theme style
    required property string label
    property bool selected: false
    // neutral: navigation/expanded choices; toggle: local on-state icon;
    // danger: explicit destructive confirmation. Focus remains independent.
    property string tone: "neutral"
    readonly property color contentInk: tone === "danger" ? style.danger
        : selected ? style.textSelected : style.textSecondary
    readonly property color iconInk: tone === "toggle" && selected ? style.accent : contentInk
    property bool available: true
    property bool filled: false
    // Background for filled buttons; override to surfaceHover inside cards.
    property color filledColor: style.surfaceRaised
    property int textSize: style.fontSizeSmall
    // Optional leading glyph. With a label it sits left of the text
    // (icon + description); alone it replaces the label (play/back/etc).
    property string iconKind: ""
    property int iconSize: 18
    property string tooltip: ""
    signal triggered()

    activeFocusOnTab: visible && available
    Accessible.role: Accessible.Button
    Accessible.name: label || tooltip
    Accessible.onPressAction: { if (available) triggered(); }
    Keys.onReturnPressed: { if (available) triggered(); }
    Keys.onEnterPressed: { if (available) triggered(); }
    Keys.onSpacePressed: { if (available) triggered(); }
    ShellToolTip {
        style: choice.style
        visible: mouse.containsMouse && choice.tooltip !== ""
        text: choice.tooltip
    }

    height: 34
    radius: style.radiusControl
    color: selected ? style.surfaceSelected
        : (mouse.containsMouse && available ? style.surfaceHover : filled ? choice.filledColor : "transparent")
    border.width: activeFocus ? 1 : 0
    border.color: style.accent
    opacity: available ? 1 : 0.45

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: choice.style.spaceSm
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: choice.label
        textFormat: Text.PlainText
        color: choice.contentInk
        font.family: choice.style.fontFamily
        font.pixelSize: choice.textSize
        font.weight: choice.selected ? Font.DemiBold : Font.Normal
        visible: choice.iconKind === "" && choice.label !== ""
    }

    RowLayout {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, Math.max(0, choice.width - 2 * choice.style.spaceSm))
        spacing: choice.style.spaceXs
        visible: choice.iconKind !== "" && choice.label !== ""

        StatusIcon {
            kind: choice.iconKind
            Layout.preferredWidth: choice.iconSize
            Layout.preferredHeight: choice.iconSize
            Layout.minimumWidth: choice.iconSize
            Layout.maximumWidth: choice.iconSize
            ink: choice.iconInk
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            text: choice.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: choice.contentInk
            font.family: choice.style.fontFamily
            font.pixelSize: choice.textSize
            font.weight: choice.selected ? Font.DemiBold : Font.Normal
        }
    }

    StatusIcon {
        anchors.centerIn: parent
        visible: choice.iconKind !== "" && choice.label === ""
        kind: choice.iconKind
        width: choice.iconSize
        height: choice.iconSize
        ink: choice.iconInk
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: choice.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: choice.triggered()
    }
}
