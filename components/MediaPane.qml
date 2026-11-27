pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Widgets
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
    readonly property string trackTitle: player?.trackTitle || player?.identity || "Media"
    readonly property string trackSubtitle: {
        const artist = player?.trackArtist || "";
        const identity = player?.identity || "";
        if (artist && identity && artist !== identity) return artist + " · " + identity;
        if (artist) return artist;
        if (identity && identity !== trackTitle) return identity;
        return "";
    }
    onPlayersChanged: { if (!players.includes(selectedPlayer)) selectedPlayer = null; }
    spacing: style.spaceMd
    function clockTime(seconds) {
        const whole = Math.floor(Math.max(0, seconds));
        return Math.floor(whole / 60) + ":" + String(whole % 60).padStart(2, "0");
    }

    GroupCard {
        Layout.fillWidth: true
        visible: !!media.player
        style: media.style
        contentSpacing: media.style.spaceMd
        RowLayout {
            Layout.fillWidth: true
            spacing: media.style.spaceMd
            ClippingRectangle {
                id: artFrame
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: media.style.radiusControl
                color: media.style.controlSurface
                border.width: 1
                border.color: media.style.separator
                Image {
                    id: cover
                    anchors.fill: parent
                    source: media.player?.trackArtUrl || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
                StatusIcon {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    visible: !cover.visible
                    kind: "music"
                    ink: media.style.textMuted
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: media.trackTitle
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: media.style.fontFamily
                    font.pixelSize: media.style.fontSizeBody
                    font.weight: Font.DemiBold
                    color: media.style.textPrimary
                }
                Text {
                    Layout.fillWidth: true
                    text: media.trackSubtitle
                    visible: text !== ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: media.style.fontFamily
                    font.pixelSize: media.style.fontSizeSmall
                    color: media.style.textSecondary
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: media.hasTimeline
            spacing: media.style.spaceSm
            Text {
                text: media.clockTime(timeline.pressed ? timeline.position * timeline.to : timeline.currentTime)
                font.family: media.style.fontFamily
                font.pixelSize: media.style.fontSizeLabel
                color: media.style.textMuted
            }
            PanelSlider {
                style: media.style
                showHandle: true
                implicitHeight: 28
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
                    running: media.visible && media.hasTimeline && !!media.player?.isPlaying && !timeline.pressed
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
                font.pixelSize: media.style.fontSizeLabel
                color: media.style.textMuted
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: media.style.spaceSm
            ChoiceButton {
                objectName: "media-shuffle"
                style: media.style
                Layout.preferredWidth: media.style.controlHeight
                visible: !!media.player?.shuffleSupported
                available: !!media.player?.canControl
                label: ""; iconKind: "shuffle"; tone: "toggle"
                selected: !!media.player?.shuffle
                tooltip: selected ? "Turn shuffle off" : "Turn shuffle on"
                Accessible.checkable: true
                Accessible.checked: selected
                onTriggered: media.player.shuffle = !media.player.shuffle
            }
            ChoiceButton {
                Layout.preferredWidth: media.style.controlHeight
                style: media.style
                label: ""; iconKind: "prev"; tooltip: "Previous track"
                available: media.player?.canGoPrevious ?? false
                onTriggered: media.player.previous()
            }
            ChoiceButton {
                Layout.preferredWidth: 44
                style: media.style
                filled: true
                label: ""; iconKind: media.player?.isPlaying ? "pause" : "play"
                tooltip: media.player?.isPlaying ? "Pause" : "Play"
                available: media.player?.canTogglePlaying ?? false
                onTriggered: media.player.togglePlaying()
            }
            ChoiceButton {
                Layout.preferredWidth: media.style.controlHeight
                style: media.style
                label: ""; iconKind: "next"; tooltip: "Next track"
                available: media.player?.canGoNext ?? false
                onTriggered: media.player.next()
            }
            ChoiceButton {
                objectName: "media-repeat"
                style: media.style
                Layout.preferredWidth: media.style.controlHeight
                visible: !!media.player?.loopSupported
                available: !!media.player?.canControl
                readonly property int mode: media.player?.loopState ?? MprisLoopState.None
                label: ""; iconKind: mode === MprisLoopState.Track ? "repeat-one" : "repeat"
                tone: "toggle"
                selected: mode !== MprisLoopState.None
                tooltip: mode === MprisLoopState.None ? "Repeat off · Repeat playlist"
                    : mode === MprisLoopState.Playlist ? "Repeating playlist · Repeat track"
                    : "Repeating track · Turn repeat off"
                onTriggered: media.player.loopState = mode === MprisLoopState.None ? MprisLoopState.Playlist
                    : mode === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.preferredHeight: 80
        visible: !media.player
        text: "No media players available"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: media.style.fontFamily
        font.pixelSize: media.style.fontSizeBody
        color: media.style.textMuted
    }

    ColumnLayout {
        Layout.fillWidth: true
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
                iconKind: "music"
                title: modelData.identity
                subtitle: modelData.trackTitle && modelData.trackTitle !== modelData.identity ? modelData.trackTitle : ""
                selected: modelData === media.player
                onTriggered: media.selectedPlayer = modelData
            }
        }
    }
}
