pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."
import "DisplayGeometry.js" as Geometry

ColumnLayout {
    id: pane
    objectName: "display-editor"
    required property Theme style
    required property var service
    property Item footerHost: null
    property real detachedBodyHeight: 0
    readonly property bool footerVisible: service.enabled || testing
    readonly property real footerHeight: footerActions.implicitHeight
    property var draft: []
    property int selected: 0
    property int seconds: 0
    property var numericEdits: ({})
    // Frozen live values for the trial summary; editorOutputs may refresh mid-trial.
    property var trialBaseline: []
    property bool reloadAfterTrial: false
    property string lastPhase: "idle"
    property string outcome: ""
    readonly property var output: draft[selected] ?? null
    readonly property var details: service.editorOutputs.find(item => item.name === output?.name)
    readonly property bool busy: service.phase !== "idle"
    readonly property bool testing: service.phase === "preview"
    readonly property var changes: describeChanges(draft)
    readonly property var trialChanges: describeChanges(service.editorPendingOutputs ?? [], trialBaseline)
    readonly property bool invalidNumbers: Object.keys(numericEdits).some(slot => numericValue(slot.split(":").pop(), numericEdits[slot]) === null)
    readonly property var independent: draft.filter(item => item.enabled && !item.mirror_of)
    readonly property bool validLayout: independent.length > 0 && draft.every(item =>
        !item.enabled || !item.mirror_of || independent.some(source => source.key === item.mirror_of))
    readonly property var issues: Geometry.issues(draft)
    readonly property var problemNames: issues.reduce((names, issue) => names.concat(issue.names), [])
    readonly property string problem: issues.length
        ? issues.map(issue => issue.text).join(" ")
        : validLayout ? "" : "Keep at least one independent display enabled and a valid source for every mirror."
    readonly property var modes: availableModes()
    readonly property var mirrorChoices: [{label:"Extend desktop", key:""}].concat(independent
        .filter(item => item.name !== output?.name).map(item => ({label:"Mirror " + item.name, key:item.key})))
    readonly property var orientations: ["Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]
    spacing: style.spaceMd

    function modeParts(value) {
        const match = /^(\d+)x(\d+)@(\d+(?:\.\d+)?)(?:Hz)?$/.exec(value);
        return match ? {width:Number(match[1]), height:Number(match[2]), refresh:Number(match[3])} : null;
    }
    function rate(value) { return Number(Number(value).toFixed(2)) + " Hz"; }
    function modeLabel(o) { return o.width + " × " + o.height + "  ·  " + rate(o.refresh); }
    function availableModes() {
        const options = (details?.modes ?? []).map(value => modeParts(value)).filter(Boolean);
        if (output?.width > 0 && !options.some(o => sameMode(o, output)))
            options.push({width:output.width, height:output.height, refresh:output.refresh});
        return options;
    }
    function sameMode(a, b) {
        return a.width === b.width && a.height === b.height && Math.abs(a.refresh - b.refresh) < 0.015;
    }
    function describeChanges(outputs, inventory) {
        const source = inventory && inventory.length ? inventory : service.editorOutputs;
        return outputs.map(o => {
            const live = source.find(item => item.name === o.name)?.current;
            if (!live) return null;
            const rows = [];
            if (o.enabled !== live.enabled) rows.push({label:"Output", value:o.enabled ? "Enabled" : "Disabled"});
            if (o.enabled && (o.width !== live.width || o.height !== live.height))
                rows.push({label:"Resolution", value:(live.width ? live.width + " × " + live.height + " → " : "") + o.width + " × " + o.height});
            if (o.enabled && Math.abs(o.refresh - live.refresh) >= 0.015)
                rows.push({label:"Refresh rate", value:(live.refresh ? rate(live.refresh) + " → " : "") + rate(o.refresh)});
            if (o.enabled && o.transform !== live.transform)
                rows.push({label:"Orientation", value:orientations[o.transform]});
            if (o.enabled && (o.mirror_of || "") !== (live.mirror_of || "")) {
                const source = outputs.find(item => item.key === o.mirror_of);
                rows.push({label:"Display mode", value:source ? "Mirror " + source.name : "Extend desktop"});
            }
            if (o.enabled && !o.mirror_of && o.scale !== live.scale)
                rows.push({label:"Scale", value:live.scale + "× → " + o.scale + "×"});
            if (o.enabled && !o.mirror_of && (o.x !== live.x || o.y !== live.y))
                rows.push({label:"Position", value:o.x + ", " + o.y});
            return rows.length ? {name:o.name, rows:rows} : null;
        }).filter(Boolean);
    }

    function reset() {
        const name = output?.name;
        draft = service.editorOutputs.map(item => Object.assign({}, item.current));
        selected = Math.max(0, draft.findIndex(item => item.name === name));
        numericEdits = {};
    }
    function update(index, fields) {
        if (!draft[index] || busy) return;
        const items = draft.slice();
        items[index] = Object.assign({}, items[index], fields);
        draft = items;
        outcome = "";
    }
    // Moves the reported displays to the nearest flush position; typed
    // coordinates cannot be dragged, so overlaps need this explicit repair.
    function tidy() {
        const moved = Geometry.arrange(draft);
        const names = Object.keys(moved);
        if (!names.length) return;
        const items = draft.slice();
        for (const name of names) {
            const index = items.findIndex(item => item.name === name);
            if (index >= 0) items[index] = Object.assign({}, items[index], moved[name]);
        }
        const edits = Object.assign({}, numericEdits);
        for (const name of names) { delete edits[name + ":x"]; delete edits[name + ":y"]; }
        numericEdits = edits;
        draft = items;
        outcome = "";
    }
    function startTrial() {
        if (busy || !validLayout || issues.length || !changes.length || invalidNumbers) return;
        pane.trialBaseline = service.editorOutputs.map(item => ({name:item.name, current:Object.assign({}, item.current)}));
        service.previewEditor(pane.draft);
    }
    function setMode(value) {
        const mode = typeof value === "string" ? modeParts(value) : value;
        if (mode) update(selected, mode);
    }
    function toggleOutput() {
        const enable = !output.enabled;
        if (enable && !output.width && modes.length) setMode(modes[0]);
        update(selected, {enabled:enable});
    }
    function numericValue(field, text) {
        const n = Number(text.trim());
        if (!text.trim() || !Number.isFinite(n) || (field === "scale"
            ? n < 0.25 || n > 8 : !Number.isInteger(n) || Math.abs(n) > 65536)) return null;
        return n;
    }
    function number(field, text) {
        if (!output || busy) return;
        numericEdits = Object.assign({}, numericEdits, {[output.name + ":" + field]: text});
        const n = numericValue(field, text);
        if (n !== null && output[field] !== n) update(selected, {[field]: n});
    }
    function fieldText(field) {
        return numericEdits[output?.name + ":" + field] ?? String(output?.[field] ?? "");
    }
    function place(index, x, y) {
        const next = Object.assign({}, numericEdits);
        delete next[draft[index].name+":x"];
        delete next[draft[index].name+":y"];
        numericEdits = next;
        update(index, {x:x, y:y});
    }
    Component.onCompleted: { reset(); service.refreshEditor(); }
    Connections {
        target: pane.service
        // A late inventory must not discard an edit in progress.
        function onEditorOutputsChanged() {
            if (pane.reloadAfterTrial || (!pane.changes.length && !pane.invalidNumbers)) {
                pane.reloadAfterTrial = false;
                pane.reset();
            } else pane.outcome = "Displays changed; discard edits to reload";
        }
        function onEditorTopologyChanged() { pane.service.refreshEditor(); }
        function onPhaseChanged() {
            if (pane.service.phase === "preview") Qt.callLater(() => revertButton.forceActiveFocus());
            if (["confirm", "revert"].includes(pane.service.phase)) pane.reloadAfterTrial = true;
            if (pane.service.phase === "idle" && ["confirm", "revert"].includes(pane.lastPhase)) {
                pane.outcome = pane.service.error ? "" : pane.lastPhase === "confirm" ? "Layout saved" : "Previous layout restored";
                pane.trialBaseline = [];
                pane.service.refreshEditor();
                Qt.callLater(() => testButton.forceActiveFocus());
            }
            pane.lastPhase = pane.service.phase;
        }
    }
    Timer {
        interval: 200
        running: pane.testing
        repeat: true
        triggeredOnStart: true
        onTriggered: pane.seconds = Math.max(0, Math.ceil((pane.service.previewUntil - Date.now()) / 1000))
    }

    component LabelText: Text {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: pane.style.textSecondary
        font.family: pane.style.fontFamily
        font.pixelSize: pane.style.fontSizeSmall
    }
    component FieldLabel: LabelText {
        font.pixelSize: pane.style.fontSizeLabel
    }
    component Picker: SettingsSelect {
        style: pane.style
        Layout.fillWidth: true
        Layout.minimumWidth: 0
    }

    SettingsNotice {
        style: pane.style
        visible: !pane.service.enabled || (!pane.draft.length && !pane.testing && !pane.service.editorError)
        iconKind: "window"
        title: !pane.service.enabled ? "Display editing is off" : pane.service.editorLoading ? "Reading displays…" : "No displays found"
        detail: !pane.service.enabled ? "Enable manual display editing in nullshell’s configuration." : ""
    }
    SettingsNotice {
        style: pane.style
        visible: !!(pane.service.editorError || pane.service.error || pane.invalidNumbers
            || (pane.draft.length && (pane.issues.length > 0 || !pane.validLayout)))
        iconKind: "warning"
        tone: "warning"
        ink: pane.service.editorError || pane.service.error || pane.invalidNumbers
            ? pane.style.danger : pane.style.accentWarm
        title: pane.issues.length ? "Check display positions" : "Check display settings"
        detail: pane.service.editorError || pane.service.error || (pane.invalidNumbers
            ? "Use a scale from 0.25 to 8 and whole-number positions."
            : pane.issues.length ? pane.problem
            : "Keep at least one independent display enabled and a valid source for every mirror.")
        actions: ChoiceButton {
            objectName: "displays-tidy"
            Layout.preferredWidth: 96
            style: pane.style
            label: "Arrange"
            tooltip: "Move the reported display to the nearest flush position"
            filled: true
            filledColor: pane.style.surfaceSelected
            visible: pane.issues.length > 0 && !pane.busy
            onTriggered: pane.tidy()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: pane.testing
        spacing: pane.style.spaceSm
        SettingsNotice {
            style: pane.style
            iconKind: "clock"
            tone: "warning"
            ink: pane.style.accentWarm
            title: pane.service.verified ? "Keep this layout?" : "Checking the new layout…"
            detail: pane.service.verified ? "The previous layout returns automatically if you do nothing." : "Waiting for Hyprland to verify the display mode."
        }
        Repeater {
            model: pane.trialChanges
            GroupCard {
                id: summary
                required property var modelData
                Layout.fillWidth: true
                style: pane.style
                title: summary.modelData.name
                iconKind: "window"
                Repeater {
                    model: summary.modelData.rows
                    RowLayout {
                        id: changeRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: pane.style.spaceMd
                        FieldLabel {
                            Layout.fillWidth: false
                            Layout.preferredWidth: 100
                            text: changeRow.modelData.label
                        }
                        LabelText { text: changeRow.modelData.value; color: pane.style.textPrimary }
                    }
                }
            }
        }
    }

    GridLayout {
        id: editor
        readonly property bool roomy: width >= 600
        readonly property bool wide: roomy && pane.detachedBodyHeight <= width * 0.83
        Layout.fillWidth: true
        visible: pane.service.enabled && !!pane.output && !pane.testing
        enabled: !pane.busy
        columns: wide ? 2 : 1
        columnSpacing: pane.style.spaceMd
        rowSpacing: pane.style.spaceMd

        GroupCard {
            objectName: "display-arrangement-card"
            Layout.fillWidth: true
            Layout.fillHeight: editor.wide
            Layout.minimumWidth: 0
            Layout.preferredWidth: pane.detachedBodyHeight > 0 && editor.width >= 800 ? 6 : 5
            style: pane.style
            stretchContent: editor.wide
            pad: editor.wide ? pane.style.spaceMd : pane.style.spaceSm
            title: "Arrangement"
            iconKind: "window"
            caption: editor.wide ? pane.draft.length + (pane.draft.length === 1 ? " display" : " displays") : "Drag to arrange"
            DisplayArrangement {
                objectName: "display-arrangement"
                Layout.fillWidth: true
                Layout.fillHeight: editor.wide
                Layout.preferredHeight: pane.detachedBodyHeight <= 0 ? (editor.wide ? 184 : 88)
                    : editor.wide ? Math.max(184, pane.detachedBodyHeight - 72)
                    : editor.roomy ? Math.max(184, pane.detachedBodyHeight - selectedDisplay.implicitHeight - 82)
                    : 112
                style: pane.style
                outputs: pane.draft
                selected: pane.selected
                problemNames: pane.problemNames
                onOutputSelected: index => pane.selected = index
                onOutputMoved: (index, x, y) => pane.place(index, x, y)
            }
            FieldLabel { visible: editor.roomy; text: "Drag to arrange; edges snap. Use X and Y for exact positions." }
        }
        GroupCard {
            id: selectedDisplay
            objectName: "display-parameters-card"
            Layout.fillWidth: true
            Layout.fillHeight: editor.wide
            Layout.minimumWidth: 0
            Layout.preferredWidth: pane.detachedBodyHeight > 0 && editor.width >= 800 ? 5 : 7
            style: pane.style
            pad: editor.wide ? pane.style.spaceMd : pane.style.spaceSm
            // The narrow editor must fit without scrolling, so it keeps 4px between groups.
            contentSpacing: editor.wide ? pane.style.spaceSm : pane.style.spaceXs
            title: "Selected display"
            RowLayout {
                Layout.fillWidth: true
                Picker {
                    objectName: "displays-output"
                    Accessible.name: "Display"
                    model: pane.draft.map(item => item.name + (item.enabled ? item.mirror_of ? "  ·  Mirrored" : "" : "  ·  Disabled"))
                    currentIndex: pane.selected
                    onActivated: index => pane.selected = index
                }
                ChoiceButton {
                    objectName: "displays-enabled"
                    Layout.preferredWidth: 96
                    style: pane.style
                    label: pane.output?.enabled ? "Enabled" : "Disabled"
                    selected: pane.output?.enabled ?? false
                    tone: "toggle"
                    filled: true
                    Accessible.checkable: true
                    Accessible.checked: pane.output?.enabled ?? false
                    onTriggered: pane.toggleOutput()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                enabled: pane.output?.enabled ?? false
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    spacing: pane.style.spaceXs
                    FieldLabel { text: "Resolution and refresh rate" }
                    Picker {
                        objectName: "displays-mode"
                        Accessible.name: "Resolution and refresh rate"
                        model: pane.modes.map(mode => pane.modeLabel(mode))
                        currentIndex: Math.max(0, pane.modes.findIndex(mode => pane.output && pane.sameMode(mode, pane.output)))
                        onActivated: index => pane.setMode(pane.modes[index])
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: pane.style.spaceXs
                    FieldLabel { text: "Orientation" }
                    Picker {
                        objectName: "displays-orientation"
                        Accessible.name: "Orientation"
                        model: pane.orientations
                        currentIndex: pane.output?.transform ?? 0
                        onActivated: index => pane.update(pane.selected, {transform:index})
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: pane.style.spaceXs
                FieldLabel { text: "Display mode" }
                Picker {
                    objectName: "displays-mirror"
                    Accessible.name: "Mirroring"
                    enabled: pane.output?.enabled ?? false
                    model: pane.mirrorChoices.map(item => item.label)
                    currentIndex: Math.max(0, pane.mirrorChoices.findIndex(item => item.key === (pane.output?.mirror_of ?? "")))
                    onActivated: index => pane.update(pane.selected, {mirror_of:pane.mirrorChoices[index].key || null})
                }
            }
            RowLayout {
                Layout.fillWidth: true
                enabled: (pane.output?.enabled ?? false) && !pane.output?.mirror_of
                Repeater {
                    model: [{key:"scale", label:"Scale"}, {key:"x", label:"Position X"}, {key:"y", label:"Position Y"}]
                    ColumnLayout {
                        id: fieldGroup
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: pane.style.spaceXs
                        FieldLabel { text: fieldGroup.modelData.label }
                        ConnectionField {
                            objectName: "displays-" + fieldGroup.modelData.key
                            Layout.fillWidth: true
                            style: pane.style
                            text: pane.fieldText(fieldGroup.modelData.key)
                            Accessible.name: fieldGroup.modelData.label
                            onTextEdited: pane.number(fieldGroup.modelData.key, text)
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
        visible: pane.footerVisible
        status: pane.testing ? "Reverts in " + pane.seconds + " s"
            : pane.outcome || (pane.busy ? "Working…" : pane.invalidNumbers ? "Check inputs"
                : pane.issues.length ? "Check positions"
                : pane.changes.length ? "Unsaved changes" : "Current layout")
        // The inline notice carries the warning; the footer only restates it.
        warning: pane.invalidNumbers && !pane.testing
        ChoiceButton {
            id: revertButton
            objectName: "displays-revert"
            Layout.preferredWidth: 128
            Layout.minimumWidth: 112
            visible: pane.testing
            style: pane.style
            label: "Revert"
            filled: true
            onTriggered: { pane.forceActiveFocus(); pane.service.revert(); }
        }
        ChoiceButton {
            objectName: "displays-confirm"
            Layout.preferredWidth: 128
            Layout.minimumWidth: 112
            visible: pane.testing
            style: pane.style
            tone: "primary"
            label: "Keep changes"
            available: pane.service.verified
            onTriggered: { pane.forceActiveFocus(); pane.service.confirm(); }
        }
        ChoiceButton {
            objectName: "displays-refresh"
            Layout.preferredWidth: 104
            visible: !pane.testing
            style: pane.style
            label: pane.changes.length || pane.invalidNumbers ? "Discard edits" : "Refresh"
            available: !pane.busy && !pane.service.editorLoading
            onTriggered: {
                if (pane.changes.length || pane.invalidNumbers) pane.reset();
                else pane.service.refreshEditor();
            }
        }
        ChoiceButton {
            id: testButton
            objectName: "displays-test"
            Layout.preferredWidth: 116
            visible: !pane.testing
            style: pane.style
            label: "Test layout"
            tone: "primary"
            available: !pane.busy && pane.validLayout && !pane.issues.length
                && pane.changes.length > 0 && !pane.invalidNumbers
            onTriggered: pane.startTrial()
        }
    }
}
