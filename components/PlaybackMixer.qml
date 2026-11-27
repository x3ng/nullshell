pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: mixer
    required property Theme style
    required property var streams
    spacing: style.spaceSm
    Repeater {
        model: mixer.streams
        delegate: RowLayout {
            id: row
            required property var modelData
            readonly property var audio: modelData.audio
            readonly property string appName: modelData.properties["application.name"] || ""
            readonly property string streamName: modelData.properties["media.name"] || modelData.description || modelData.name || ""
            Layout.fillWidth: true
            spacing: mixer.style.spaceSm
            FilledSlider {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                style: mixer.style
                objectName: "stream-volume-" + row.modelData.id
                label: row.appName && row.streamName && row.appName !== row.streamName
                    ? row.appName + " · " + row.streamName : row.appName || row.streamName
                value: row.audio?.volume ?? 0
                available: !!row.audio
                onEdited: value => { if (row.audio) row.audio.volume = value; }
            }
            ChoiceButton {
                objectName: "stream-mute-" + row.modelData.id
                Layout.preferredWidth: 72
                Layout.preferredHeight: 36
                style: mixer.style
                filled: true
                label: selected ? "Unmute" : "Mute"
                selected: row.audio?.muted ?? false
                available: !!row.audio
                onTriggered: { if (row.audio) row.audio.muted = !row.audio.muted; }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        Layout.preferredHeight: 80
        visible: mixer.streams.length === 0
        text: "No active playback streams"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: mixer.style.fontFamily
        font.pixelSize: mixer.style.fontSizeBody
        color: mixer.style.textMuted
    }
}
