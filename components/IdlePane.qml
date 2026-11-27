pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."
import "../ConfigRules.js" as Rules

ColumnLayout {
    id: pane
    objectName: "idle-editor"
    required property Theme style
    required property var preferences
    required property var services
    property Item footerHost: null
    readonly property bool footerVisible: true
    readonly property real footerHeight: footerActions.implicitHeight
    property var draft: ({})
    property var observed: ({})
    readonly property var rows: [
        {key: "dimSeconds", label: "Dim display", icon: "brightness"},
        {key: "lockSeconds", label: "Lock screen", icon: "lock"},
        {key: "displayOffSeconds", label: "Turn off displays", icon: "window"}
    ]
    readonly property var presets: [
        {id: "off", label: "Off", minutes: 0},
        {id: "30", label: "30m", minutes: 30},
        {id: "60", label: "1h", minutes: 60},
        {id: "120", label: "2h", minutes: 120},
        {id: "always", label: "Always", minutes: -1}
    ]
    readonly property var numbers: ({
        dimSeconds: durationSeconds(draft.dimSeconds),
        lockSeconds: durationSeconds(draft.lockSeconds),
        displayOffSeconds: durationSeconds(draft.displayOffSeconds)
    })
    readonly property bool valid: Rules.validIdleDeadlines(numbers)
    readonly property bool changed: rows.some(row => numbers[row.key] !== preferences.values[row.key])
    spacing: style.spaceMd

    function durationSeconds(input) {
        const s = String(input ?? "").trim();
        if (/^\d{1,5}$/.test(s)) return Number(s);
        const clock = /^(\d{1,4}):([0-5]\d)$/.exec(s);
        return clock ? Number(clock[1]) * 60 + Number(clock[2]) : NaN;
    }
    function formatDuration(seconds) {
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
    }

    function resetDraft() {
        const fields = {};
        for (const row of rows) fields[row.key] = formatDuration(preferences.values[row.key]);
        observed = preferences.values;
        draft = fields;
    }
    function edit(key, text) {
        draft = Object.assign({}, draft, {[key]: text});
    }
    function normalize(key, text) {
        const seconds = durationSeconds(text);
        if (Number.isInteger(seconds) && seconds >= 1 && seconds <= Rules.idleMaximumSeconds())
            edit(key, formatDuration(seconds));
    }
    function selectPreset(preset) {
        if (preset.id === "off") {
            services.setKeepAwake(false);
        } else if (preset.id === "always") {
            if (services.keepAwakeRequested && services.keepAwakeUntil === 0) {
                services.setKeepAwake(false);
            } else {
                services.keepAwakeFor(0);
                services.setKeepAwake(true);
            }
        } else {
            services.setKeepAwake(false);
            services.keepAwakeFor(preset.minutes);
        }
    }
    Component.onCompleted: resetDraft()
    Connections {
        target: pane.preferences
        function onOverriddenChanged() { pane.resetDraft(); }
        function onValuesChanged() {
            if (pane.rows.some(row => pane.observed[row.key] !== pane.preferences.values[row.key])) pane.resetDraft();
        }
    }

    // Unified Keep Awake card: permanent, preset durations and custom timer in one place.
    GroupCard {
        Layout.fillWidth: true
        style: pane.style
        contentSpacing: pane.style.spaceSm

        RowLayout {
            Layout.fillWidth: true
            spacing: pane.style.spaceSm

            StatusIcon {
                kind: "coffee"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                ink: pane.services.keepAwake ? pane.style.accent : pane.style.textSecondary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: pane.services.keepAwakeUntil > 0
                        ? "Keep awake until " + Qt.formatTime(new Date(pane.services.keepAwakeUntil), "hh:mm")
                        : "Keep awake"
                    color: pane.style.textPrimary
                    font.family: pane.style.fontFamily
                    font.pixelSize: pane.style.fontSizeBody
                    font.weight: Font.Medium
                }

                Text {
                    Layout.fillWidth: true
                    text: !pane.services.keepAwake ? "Automatic dimming and lock are active"
                        : pane.services.keepAwakeUntil > 0
                            ? (pane.services.keepAwakeRequested ? "Timer active · Always is also on" : "Idle timers resume automatically when the timer ends")
                            : "Idle timers paused indefinitely"
                    color: pane.style.textMuted
                    font.family: pane.style.fontFamily
                    font.pixelSize: pane.style.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: pane.presets
                delegate: ChoiceButton {
                    required property var modelData
                    objectName: modelData.id === "always" ? "idle-keep-awake" : "awake-preset-" + modelData.id
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    compact: true
                    filled: true
                    style: pane.style
                    label: modelData.label
                    tone: "toggle"
                    selected: modelData.id === "off" ? !pane.services.keepAwake
                        : modelData.id === "always" ? (pane.services.keepAwakeRequested && pane.services.keepAwakeUntil === 0)
                        : false
                    available: pane.services.keepAwakeReady
                    onTriggered: pane.selectPreset(modelData)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: pane.style.separator
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: pane.style.spaceSm

            Text {
                Layout.fillWidth: true
                text: pane.services.keepAwakeUntil > 0 ? "Active custom timer" : "Custom timer"
                color: pane.style.textSecondary
                font.family: pane.style.fontFamily
                font.pixelSize: pane.style.fontSizeSmall
            }

            ConnectionField {
                id: duration
                objectName: "awake-duration"
                style: pane.style
                Layout.preferredWidth: 84
                Layout.preferredHeight: 32
                visible: !pane.services.keepAwakeUntil
                placeholderText: " min"
                horizontalAlignment: Text.AlignHCenter
                validator: IntValidator { bottom: 1; top: 1440 }
                onAccepted: if (acceptableInput) { pane.services.setKeepAwake(false); pane.services.keepAwakeFor(Number(text)); }
            }

            ChoiceButton {
                objectName: "awake-duration-apply"
                Layout.preferredWidth: 88
                compact: true
                style: pane.style
                filled: true
                label: pane.services.keepAwakeUntil > 0 ? "End timer" : "Start"
                available: pane.services.keepAwakeReady && (pane.services.keepAwakeUntil > 0 || duration.acceptableInput)
                onTriggered: {
                    if (pane.services.keepAwakeUntil > 0) {
                        pane.services.keepAwakeFor(0);
                    } else {
                        pane.services.setKeepAwake(false);
                        pane.services.keepAwakeFor(Number(duration.text));
                    }
                }
            }
        }
    }

    GroupCard {
        Layout.fillWidth: true
        style: pane.style
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: pane.rows
                ColumnLayout {
                    id: entry
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        visible: entry.index > 0
                        color: pane.style.separator
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: pane.style.spaceXs
                        Layout.bottomMargin: pane.style.spaceXs
                        spacing: pane.style.spaceMd
                        StatusIcon {
                            kind: entry.modelData.icon
                            ink: pane.style.textSecondary
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                        }
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.label
                            color: pane.style.textPrimary
                            font.family: pane.style.fontFamily
                            font.pixelSize: pane.style.fontSizeBody
                        }
                        ConnectionField {
                            objectName: "idle-" + entry.modelData.key
                            style: pane.style
                            Layout.preferredWidth: 88
                            Layout.preferredHeight: pane.style.controlHeight
                            enabled: pane.preferences.ready && !pane.preferences.saving
                            text: pane.draft[entry.modelData.key] ?? ""
                            horizontalAlignment: Text.AlignHCenter
                            Accessible.name: entry.modelData.label + " (minutes and seconds)"
                            onTextEdited: pane.edit(entry.modelData.key, text)
                            onEditingFinished: pane.normalize(entry.modelData.key, text)
                        }
                    }
                }
            }
        }
    }

    SettingsActions {
        id: footerActions
        style: pane.style
        host: pane.footerHost
        parent: pane.footerHost ?? pane
        status: pane.preferences.error || (!pane.valid ? "Use min:sec. Dim first, then lock, then turn off displays."
            : pane.changed ? "Unsaved changes" : pane.preferences.overridden ? "Saved timers" : "Configuration defaults")
        warning: !!pane.preferences.error || !pane.valid
        ChoiceButton {
            objectName: "idle-reset"
            Layout.preferredWidth: 112
            style: pane.style
            label: "Use defaults"
            tooltip: "Restore timer values from configuration"
            available: pane.preferences.ready && !pane.preferences.saving && (pane.preferences.overridden || pane.changed)
            onTriggered: {
                if (pane.preferences.overridden) pane.preferences.store(null);
                else pane.resetDraft();
            }
        }
        ChoiceButton {
            objectName: "idle-save"
            Layout.preferredWidth: 102
            style: pane.style
            label: pane.preferences.saving ? "Saving…" : "Save timers"
            tone: "primary"
            available: pane.preferences.ready && !pane.preferences.saving && pane.valid && pane.changed
            onTriggered: pane.preferences.store(pane.numbers)
        }
    }
}
