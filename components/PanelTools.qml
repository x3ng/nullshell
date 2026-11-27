pragma ComponentBehavior: Bound

import QtQuick
import ".."

// Dynamic session status indicators for the overview footer. Icons appear only
// while a non-default Quickshell state is active; left-click opens its owning
// page and right-click resets/disables the state in place.
Row {
    id: tools
    required property Theme style
    required property var services
    required property var actions
    property var notifs: null
    property var appearance: null
    property var keyboard: null

    readonly property string activeProfile: services.controls?.powerAvailable ? (services.controls?.powerProfile ?? "") : ""
    readonly property var indicators: [
        {
            name: "footer-power-status",
            active: activeProfile === "power-saver" || activeProfile === "performance",
            icon: activeProfile === "performance" ? "gauge" : "leaf",
            muted: false,
            level: 1,
            caution: activeProfile === "performance",
            openRoute: "session",
            dismissKind: "power-reset",
            tooltip: (activeProfile === "performance" ? "Power profile: Performance" : "Power profile: Power saver")
                + "\nClick for Power · Right-click for Balanced"
        },
        {
            name: "footer-appearance-status",
            active: (appearance?.automatic ?? false) && (appearance?.overrideUntil ?? 0) > 0,
            icon: "appearance",
            muted: false,
            level: (appearance?.darkMode ?? true) ? -1 : 1,
            caution: false,
            openRoute: "appearance",
            dismissKind: "appearance-resume",
            tooltip: "Automatic appearance temporarily overridden\nClick for Appearance · Right-click to resume auto"
        },
        {
            name: "footer-keyboard-status",
            active: keyboard?.shown === true,
            icon: "keyboard",
            muted: false,
            level: 1,
            caution: false,
            openRoute: "keyboard",
            dismissKind: "keyboard",
            tooltip: "Screen keyboard active\nClick to hide"
        },
        {
            name: "footer-dnd-status",
            active: notifs?.doNotDisturb === true,
            icon: "bell-off",
            muted: false,
            level: 1,
            caution: true,
            openRoute: "notifications",
            dismissKind: "notifications-resume",
            tooltip: ((notifs?.quietUntil ?? 0) > 0
                ? "Notifications paused until " + Qt.formatTime(new Date(notifs.quietUntil), "hh:mm")
                : "Notifications paused") + "\nClick for Notifications · Right-click to resume"
        },
        {
            name: "footer-mic-status",
            active: services.source?.audio?.muted === true,
            icon: "mic",
            muted: true,
            level: 1,
            caution: true,
            openRoute: "audio",
            dismissKind: "mic-mute",
            tooltip: "Microphone muted\nClick for Audio · Right-click to unmute"
        },
        {
            name: "footer-awake-status",
            active: services.keepAwake === true,
            icon: "coffee",
            muted: false,
            level: 1,
            caution: false,
            openRoute: "idle",
            dismissKind: "awake-off",
            tooltip: (services.keepAwakeUntil > 0
                ? "Keep awake until " + Qt.formatTime(new Date(services.keepAwakeUntil), "hh:mm")
                    + (services.keepAwakeRequested ? " · Always also on" : "")
                : "Keep awake active") + "\nClick for Idle settings · Right-click to turn off"
        }
    ]
    readonly property bool hasStatus: indicators.some(entry => entry.active)

    function dismissIndicator(kind) {
        if (kind === "awake-off") tools.services.setKeepAwake(false);
        else if (kind === "power-reset") tools.actions.execute("power:balanced");
        else tools.actions.execute(kind);
    }

    height: 30
    spacing: 2

    Repeater {
        model: tools.indicators
        Rectangle {
            id: indicator
            required property var modelData
            objectName: modelData.name
            visible: modelData.active
            width: 26
            height: 30
            radius: tools.style.radiusControl
            color: indicatorMouse.containsMouse ? tools.style.surfaceHover : "transparent"
            function triggered() { tools.actions.execute(indicator.modelData.openRoute); }
            function secondaryTriggered() { tools.dismissIndicator(indicator.modelData.dismissKind); }
            Accessible.role: Accessible.Button
            Accessible.name: modelData.tooltip
            Accessible.onPressAction: indicator.triggered()

            StatusIcon {
                anchors.centerIn: parent
                width: 16
                height: 16
                strokeWidth: 1.6
                kind: indicator.modelData.icon
                muted: indicator.modelData.muted
                level: indicator.modelData.level
                ink: indicator.modelData.caution ? tools.style.accentWarm : tools.style.accent
            }

            MouseArea {
                id: indicatorMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: event => {
                    if (event.button === Qt.LeftButton) indicator.triggered();
                    else indicator.secondaryTriggered();
                }
            }

            ShellToolTip {
                style: tools.style
                visible: indicatorMouse.containsMouse && indicator.modelData.tooltip !== ""
                text: indicator.modelData.tooltip
            }
        }
    }
}
