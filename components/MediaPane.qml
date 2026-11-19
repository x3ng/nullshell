pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: media
    objectName: "media-pane"
    required property Theme style
    required property var services
    readonly property var players: services.players
    property var selectedPlayer: null
    readonly property var player: selectedPlayer ?? services.player
    readonly property bool hasTimeline: !!player?.positionSupported && !!player?.lengthSupported && player.length > 0
    onPlayersChanged: { if (!players.includes(selectedPlayer)) selectedPlayer = null; }
    spacing: style.spaceSm
    function clockTime(seconds) {
        const whole = Math.floor(Math.max(0, seconds));
        return Math.floor(whole / 60) + ":" + String(whole % 60).padStart(2, "0");
    }
    Text {
        Layout.fillWidth: true
        text: media.player?.trackTitle || media.player?.identity || "No media players available"
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: media.style.fontFamily
        font.pixelSize: media.style.fontSizeBody
        font.weight: Font.DemiBold
        color: media.style.textPrimary
    }
    Text {
        Layout.fillWidth: true
        text: media.player?.trackArtist || media.player?.identity || ""
        visible: text !== ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font.family: media.style.fontFamily
        font.pixelSize: media.style.fontSizeSmall
        color: media.style.textMuted
    }
    RowLayout {
        Layout.fillWidth: true
        visible: media.hasTimeline
        Text {
            text: media.clockTime(timeline.pressed ? timeline.position * timeline.to : timeline.currentTime)
            font.family: media.style.fontFamily
            font.pixelSize: media.style.fontSizeSmall
            color: media.style.textSecondary
        }
        PanelSlider {
            style: media.style
            showHandle: true
            implicitHeight: 32
            id: timeline
            objectName: "media-position"
            Layout.fillWidth: true
            Accessible.name: "Track position"
            enabled: media.hasTimeline && !!media.player?.canSeek
            to: media.hasTimeline ? media.player.length : 1
            live: false
            property int tick: 0
            readonly property real currentTime: {
                const sample = tick;
                return media.hasTimeline ? media.player.position : 0;
            }
            property var dragPlayer: null
            property var dragTrack: null
            value: currentTime
            function seek(seconds) {
                if (enabled) media.player.position = Math.max(0, Math.min(to, seconds));
                tick++;
            }
            Keys.onLeftPressed: seek(currentTime - 5)
            Keys.onRightPressed: seek(currentTime + 5)
            Timer {
                interval: 500
                running: media.visible && media.hasTimeline && media.player.isPlaying && !timeline.pressed
                repeat: true
                onTriggered: timeline.tick++
            }
            onPressedChanged: {
                if (pressed) {
                    dragPlayer = media.player;
                    dragTrack = media.player?.uniqueId || "";
                } else if (enabled && dragPlayer === media.player && dragTrack === (media.player.uniqueId || "")) {
                    seek(position * to);
                }
            }
        }
        Text {
            text: media.clockTime(timeline.to)
            font.family: media.style.fontFamily
            font.pixelSize: media.style.fontSizeSmall
            color: media.style.textSecondary
        }
    }
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        visible: !!media.player
        ChoiceButton {
            Layout.preferredWidth: 44
            style: media.style
            label: ""; iconKind: "prev"; tooltip: "Previous track"
            available: media.player?.canGoPrevious ?? false
            onTriggered: media.player.previous()
        }
        ChoiceButton {
            Layout.preferredWidth: 52
            style: media.style
            filled: true
            label: ""; iconKind: media.player?.isPlaying ? "pause" : "play"
            tooltip: media.player?.isPlaying ? "Pause" : "Play"
            available: media.player?.canTogglePlaying ?? false
            onTriggered: media.player.togglePlaying()
        }
        ChoiceButton {
            Layout.preferredWidth: 44
            style: media.style
            label: ""; iconKind: "next"; tooltip: "Next track"
            available: media.player?.canGoNext ?? false
            onTriggered: media.player.next()
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: media.style.spaceSm
        spacing: media.style.spaceXs
        visible: media.players.length > 1
        Repeater {
            model: media.players.length > 1 ? media.players : []
            delegate: DeviceRow {
                required property var modelData
                objectName: "select-player-" + modelData.identity
                Layout.fillWidth: true
                style: media.style
                selectionOnly: true
                title: modelData.identity
                selected: modelData === media.player
                onTriggered: media.selectedPlayer = modelData
            }
        }
    }
}
