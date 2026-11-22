pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: pane
    objectName: "idle-editor"
    required property Theme style
    required property var preferences
    required property var services
    property var draft: ({})
    readonly property var rows: [
        {key:"dimSeconds", label:"Dim display after"},
        {key:"lockSeconds", label:"Lock screen after"},
        {key:"displayOffSeconds", label:"Turn off displays after"}
    ]
    readonly property var numbers: ({dimSeconds: Number(draft.dimSeconds), lockSeconds: Number(draft.lockSeconds),
        displayOffSeconds: Number(draft.displayOffSeconds)})
    readonly property bool valid: Object.values(numbers).every(n => Number.isInteger(n) && n >= 1 && n <= 86400)
        && numbers.dimSeconds < numbers.lockSeconds && numbers.lockSeconds < numbers.displayOffSeconds
    readonly property bool changed: JSON.stringify(numbers) !== JSON.stringify(preferences.values)
    spacing: style.spaceSm

    function resetDraft() {
        const fields = {};
        for (const row of rows) fields[row.key] = String(preferences.values[row.key]);
        draft = fields;
    }
    function edit(key, text) {
        draft = Object.assign({}, draft, {[key]: text});
    }
    Component.onCompleted: resetDraft()
    Connections {
        target: pane.preferences
        function onValuesChanged() { pane.resetDraft(); }
    }

    component Hint: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: pane.style.textSecondary
        font.family: pane.style.fontFamily
        font.pixelSize: pane.style.fontSizeSmall
    }

    RowLayout {
        Layout.fillWidth: true
        Hint {
            text: !pane.services.keepAwake ? "Idle timers are active."
                : pane.services.keepAwakeRequested ? "Idle timers are paused by Keep awake."
                : "Idle timers are paused until " + Qt.formatTime(new Date(pane.services.keepAwakeUntil), "hh:mm") + "."
        }
        ChoiceButton {
            objectName: "idle-keep-awake"
            Layout.preferredWidth: 145
            style: pane.style
            label: pane.services.keepAwake ? "Resume idle timers" : "Keep awake"
            available: pane.services.keepAwakeReady
            onTriggered: pane.services.setKeepAwake(!pane.services.keepAwake)
        }
    }
    Hint { text: "Time since the last activity. These timers do not suspend the computer." }
    Repeater {
        model: pane.rows
        RowLayout {
            id: entry
            required property var modelData
            Layout.fillWidth: true
            spacing: pane.style.spaceSm
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
                Layout.preferredWidth: 84
                enabled: pane.preferences.ready && !pane.preferences.saving
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 86400; locale: "C" }
                text: pane.draft[entry.modelData.key] ?? ""
                Accessible.name: entry.modelData.label + " (seconds)"
                onTextEdited: pane.edit(entry.modelData.key, text)
            }
            Text {
                text: "seconds"
                color: pane.style.textSecondary
                font.family: pane.style.fontFamily
                font.pixelSize: pane.style.fontSizeSmall
            }
        }
    }
    Hint {
        text: pane.preferences.error || (!pane.valid ? "Use whole seconds: dim < lock < display off."
            : pane.preferences.overridden ? "Using your saved idle settings." : "Using configuration defaults.")
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
            filled: true
            available: pane.preferences.ready && !pane.preferences.saving && pane.valid && pane.changed
            onTriggered: pane.preferences.store(pane.numbers)
        }
    }
}
