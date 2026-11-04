pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import ".."

TextField {
    id: field
    required property Theme style
    property bool secret: false
    property bool revealed: false
    implicitHeight: 40
    padding: 10
    rightPadding: secret ? 64 : 10
    selectByMouse: true
    echoMode: secret && !revealed ? TextInput.Password : TextInput.Normal
    color: style.textPrimary
    placeholderTextColor: style.textMuted
    selectionColor: style.surfaceSelected
    selectedTextColor: style.textSelected
    font.family: style.fontFamily
    font.pixelSize: style.fontSizeBody
    background: Rectangle {
        radius: field.style.radiusControl
        color: field.style.panelSurface
        border.width: 1
        border.color: field.activeFocus ? field.style.accent : field.style.separator
    }
    ChoiceButton {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 52
        height: 30
        visible: field.secret
        style: field.style
        label: field.revealed ? "Hide" : "Show"
        onTriggered: { field.revealed = !field.revealed; field.forceActiveFocus(); }
    }
}
