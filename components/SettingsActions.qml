import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: bar
    required property Theme style
    property Item host: null
    property string status: ""
    property bool warning: false
    default property alias buttons: row.data

    width: host ? host.width : implicitWidth
    Layout.fillWidth: true
    spacing: style.spaceSm

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: bar.style.separator
    }

    RowLayout {
        id: row
        Layout.fillWidth: true
        spacing: bar.style.spaceSm
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: text !== ""
            text: bar.status
            wrapMode: Text.WordWrap
            color: bar.warning ? bar.style.danger : bar.style.textSecondary
            font.family: bar.style.fontFamily
            font.pixelSize: bar.style.fontSizeSmall
        }
    }
}
