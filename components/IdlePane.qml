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
        selected: pane.services.keepAwake
        available: pane.services.keepAwakeReady
        onTriggered: pane.services.setKeepAwake(!pane.services.keepAwake)
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
