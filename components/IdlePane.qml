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
    property var draft: ({})
    property var observed: ({})
    readonly property var rows: [
        {key:"dimSeconds", label:"Dim display", icon:"brightness"},
        {key:"lockSeconds", label:"Lock screen", icon:"lock"},
        {key:"displayOffSeconds", label:"Turn off displays", icon:"window"}
    ]
    readonly property var numbers: ({dimSeconds: durationSeconds(draft.dimSeconds), lockSeconds: durationSeconds(draft.lockSeconds),
        displayOffSeconds: durationSeconds(draft.displayOffSeconds)})
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
    Component.onCompleted: resetDraft()
    Connections {
        target: pane.preferences
        function onOverriddenChanged() { pane.resetDraft(); }
        function onValuesChanged() {
            // A config reload can reallocate an unchanged idle object. Do not
            // discard an in-progress edit when only unrelated settings changed.
            if (pane.rows.some(row => pane.observed[row.key] !== pane.preferences.values[row.key])) pane.resetDraft();
        }
    }

    component Hint: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: pane.style.textSecondary
        font.family: pane.style.fontFamily
        font.pixelSize: pane.style.fontSizeSmall
    }

    SettingsNotice {
        style: pane.style
        title: pane.services.keepAwake ? "Idle timers paused" : "Idle timers active"
        iconKind: "clock"
        ink: pane.services.keepAwake ? pane.style.accentWarm : pane.style.accent
        detail: !pane.services.keepAwake ? "Actions run after the last input."
            : pane.services.keepAwakeRequested ? "Keep awake is on."
            : "Keep awake until " + Qt.formatTime(new Date(pane.services.keepAwakeUntil), "hh:mm") + "."
        actions: ChoiceButton {
            objectName: "idle-keep-awake"
            Layout.preferredWidth: 115
            style: pane.style
            label: pane.services.keepAwake ? "Resume timers" : "Keep awake"
            filled: true
            filledColor: pane.style.surfaceSelected
            available: pane.services.keepAwakeReady
            onTriggered: pane.services.setKeepAwake(!pane.services.keepAwake)
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: pane.style.spaceSm
        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: "After inactivity"
                color: pane.style.textPrimary
                font.family: pane.style.fontFamily
                font.pixelSize: pane.style.fontSizeBody
                font.weight: Font.DemiBold
            }
            Text {
                text: "min:sec"
                color: pane.style.textSecondary
                font.family: pane.style.fontFamily
                font.pixelSize: pane.style.fontSizeLabel
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: timers.implicitHeight + 2 * pane.style.spaceXs
            color: pane.style.surfaceRaised
            radius: pane.style.radiusCard
            border.width: 1
            border.color: pane.style.separator
            ColumnLayout {
                id: timers
                anchors.fill: parent
                anchors.margins: pane.style.spaceXs
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
                            Layout.margins: pane.style.spaceSm
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
    }
    Hint {
        text: pane.preferences.error || (!pane.valid ? "Enter min:sec or seconds. Dim first, then lock, then turn off displays."
            : pane.changed ? "Unsaved changes" : pane.preferences.overridden ? "Saved idle settings" : "Configuration defaults")
        color: pane.preferences.error || !pane.valid ? pane.style.danger : pane.style.textSecondary
    }
    RowLayout {
        Layout.fillWidth: true
        ChoiceButton {
            objectName: "idle-reset"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            style: pane.style
            label: "Restore defaults"
            available: pane.preferences.ready && !pane.preferences.saving && (pane.preferences.overridden || pane.changed)
            onTriggered: {
                if (pane.preferences.overridden) pane.preferences.store(null);
                else pane.resetDraft();
            }
        }
        ChoiceButton {
            objectName: "idle-save"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            style: pane.style
            label: pane.preferences.saving ? "Saving…" : "Save timers"
            tone: "primary"
            available: pane.preferences.ready && !pane.preferences.saving && pane.valid && pane.changed
            onTriggered: pane.preferences.store(pane.numbers)
        }
    }
}
