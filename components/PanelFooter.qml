pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: footer
    required property Theme style
    implicitHeight: 48
    color: "transparent"
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 1
        color: footer.style.separator
    }
    RowLayout {
        anchors.fill: parent
        anchors.topMargin: 9
        anchors.bottomMargin: 3
        spacing: 18
        Repeater {
            model: ["↑ ↓  Navigate", "esc  Back"]
            Text {
                required property string modelData
                text: modelData
                font.family: footer.style.fontFamily
                font.pixelSize: footer.style.fontSizeSmall
                color: footer.style.textMuted
            }
        }
        Item { Layout.fillWidth: true }
    }
}
