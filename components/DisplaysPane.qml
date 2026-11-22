pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: pane
    objectName: "display-editor"
    required property Theme style
    required property var service
    property Item footerHost: null
    readonly property bool footerVisible: service.enabled || testing
    readonly property real footerHeight: footerActions.implicitHeight
    property var draft: []
    property int selected: 0
    property int seconds: 0
    property var numericEdits: ({})
    property string lastPhase: "idle"
    property string outcome: ""
    readonly property var output: draft[selected] ?? null
    readonly property var details: service.editorOutputs.find(item => item.name === output?.name)
    readonly property bool busy: service.phase !== "idle"
    readonly property bool testing: service.phase === "preview"
    readonly property var changes: describeChanges(draft)
    readonly property var trialChanges: describeChanges(service.editorPendingOutputs ?? [])
    readonly property bool invalidNumbers: Object.keys(numericEdits).some(slot => numericValue(slot.split(":").pop(), numericEdits[slot]) === null)
    readonly property var independent: draft.filter(item => item.enabled && !item.mirror_of)
    readonly property bool validLayout: independent.length > 0 && draft.every(item =>
        !item.enabled || !item.mirror_of || independent.some(source => source.key === item.mirror_of))
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
    function describeChanges(outputs) {
        return outputs.map(o => {
            const live = service.editorOutputs.find(item => item.name === o.name)?.current;
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
    function layoutWidth(o) { return (o.transform % 2 ? o.height : o.width) / Math.max(0.25, o.scale); }
    function layoutHeight(o) { return (o.transform % 2 ? o.width : o.height) / Math.max(0.25, o.scale); }

    Component.onCompleted: { reset(); service.refreshEditor(); }
    Connections {
        target: pane.service
        function onEditorOutputsChanged() { pane.reset(); }
        function onEditorTopologyChanged() { pane.service.refreshEditor(); }
        function onPhaseChanged() {
            if (pane.service.phase === "idle" && ["confirm", "revert"].includes(pane.lastPhase)) {
                pane.outcome = pane.service.error ? "" : pane.lastPhase === "confirm" ? "Layout saved" : "Previous layout restored";
                pane.service.refreshEditor();
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
    component Heading: LabelText {
        color: pane.style.textPrimary
        font.pixelSize: pane.style.fontSizeBody
        font.weight: Font.DemiBold
    }
    component Picker: Basic.ComboBox {
        id: picker
        Layout.fillWidth: true
        implicitHeight: pane.style.fieldHeight
        leftPadding: pane.style.spaceMd
        rightPadding: 2 * pane.style.spaceMd
        font.family: pane.style.fontFamily
        font.pixelSize: pane.style.fontSizeBody
        contentItem: Text {
            text: picker.displayText
            font: picker.font
            color: pane.style.textPrimary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: Text {
            x: picker.width - width - pane.style.spaceMd
            y: (picker.height - height) / 2
            text: "▾"
            color: pane.style.textSecondary
            font.pixelSize: pane.style.fontSizeSmall
        }
        background: Rectangle {
            radius: pane.style.radiusControl
            color: pane.style.panelSurface
            border.color: picker.activeFocus ? pane.style.accent : pane.style.separator
            border.width: 1
        }
        delegate: Basic.ItemDelegate {
            id: option
            required property string modelData
            required property int index
            width: picker.width - 2
            highlighted: picker.highlightedIndex === index
            contentItem: Text {
                text: option.modelData
                font: picker.font
                color: pane.style.textPrimary
                elide: Text.ElideRight
            }
            background: Rectangle {
                color: option.highlighted || option.hovered ? pane.style.surfaceSelected : pane.style.panelSurface
            }
        }
        popup: Basic.Popup {
            y: picker.height
            width: picker.width
            padding: 1
            implicitHeight: Math.min(240, contentItem.implicitHeight + 2)
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: picker.delegateModel
                currentIndex: picker.highlightedIndex
            }
            background: Rectangle {
                color: pane.style.panelSurface
                border.color: pane.style.separator
                border.width: 1
                radius: pane.style.radiusControl
            }
        }
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
        visible: !!(pane.service.editorError || pane.service.error || pane.invalidNumbers || (pane.draft.length && !pane.validLayout))
        iconKind: "warning"
        ink: pane.style.danger
        title: "Check display settings"
        detail: pane.service.editorError || pane.service.error || (pane.invalidNumbers
            ? "Use a scale from 0.25 to 8 and whole-number positions."
            : "Keep at least one independent display enabled and a valid source for every mirror.")
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: pane.testing
        spacing: pane.style.spaceSm
        SettingsNotice {
            style: pane.style
            iconKind: "clock"
            ink: pane.style.accentWarm
            title: pane.service.verified ? "Keep this layout?" : "Checking the new layout…"
            detail: pane.service.verified ? "Reverts in " + pane.seconds + " s unless you keep it." : "Waiting for Hyprland to verify the display mode."
        }
        Repeater {
            model: pane.trialChanges
            ColumnLayout {
                id: summary
                required property var modelData
                Layout.fillWidth: true
                spacing: pane.style.spaceXs
                Heading { text: summary.modelData.name }
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

    ColumnLayout {
        Layout.fillWidth: true
        visible: pane.service.enabled && !!pane.output && !pane.testing
        enabled: !pane.busy
        spacing: pane.style.spaceSm

        RowLayout {
            Layout.fillWidth: true
            Heading { text: "Arrangement" }
            FieldLabel { Layout.fillWidth: false; text: pane.draft.length + (pane.draft.length === 1 ? " display" : " displays") }
        }
        Rectangle {
            id: canvas
            Layout.fillWidth: true
            Layout.preferredHeight: 104
            radius: pane.style.radiusControl
            color: pane.style.backgroundSurface
            border.color: pane.style.separator
            border.width: 1
            clip: true
            readonly property var screens: pane.independent.filter(o => o.width > 0 && o.height > 0)
            readonly property real leftEdge: screens.length ? Math.min(...screens.map(o => o.x)) : 0
            readonly property real topEdge: screens.length ? Math.min(...screens.map(o => o.y)) : 0
            readonly property real spanX: screens.length ? Math.max(1, Math.max(...screens.map(o => o.x + pane.layoutWidth(o))) - leftEdge) : 1
            readonly property real spanY: screens.length ? Math.max(1, Math.max(...screens.map(o => o.y + pane.layoutHeight(o))) - topEdge) : 1
            readonly property real factor: Math.max(0.0001, Math.min((width - 24) / spanX, (height - 24) / spanY))
            Repeater {
                model: pane.draft
                Rectangle {
                    id: screenRect
                    required property var modelData
                    required property int index
                    property point offset: Qt.point(0, 0)
                    visible: modelData.enabled && !modelData.mirror_of
                    x: (canvas.width - canvas.spanX * canvas.factor) / 2 + (modelData.x - canvas.leftEdge) * canvas.factor + offset.x
                    y: (canvas.height - canvas.spanY * canvas.factor) / 2 + (modelData.y - canvas.topEdge) * canvas.factor + offset.y
                    width: Math.max(8, pane.layoutWidth(modelData) * canvas.factor)
                    height: Math.max(8, pane.layoutHeight(modelData) * canvas.factor)
                    radius: pane.style.radiusCard
                    color: pane.selected === index ? pane.style.surfaceSelected : pane.style.surfaceRaised
                    border.color: pane.selected === index ? pane.style.accent : pane.style.outline
                    z: pane.selected === index ? 1 : 0
                    border.width: 1
                    Text {
                        anchors.fill: parent
                        anchors.margins: 3
                        text: screenRect.modelData.name
                        color: pane.style.textPrimary
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        font.family: pane.style.fontFamily
                        font.pixelSize: pane.style.fontSizeSmall
                        font.weight: pane.selected === screenRect.index ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: dragScreen
                        anchors.fill: parent
                        property point origin
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPressed: mouse => {
                            pane.selected = screenRect.index;
                            origin = mapToItem(canvas, mouse.x, mouse.y);
                        }
                        onPositionChanged: mouse => {
                            if (!pressed) return;
                            const point = mapToItem(canvas, mouse.x, mouse.y);
                            screenRect.offset = Qt.point(point.x - origin.x, point.y - origin.y);
                        }
                        onCanceled: screenRect.offset = Qt.point(0, 0)
                        onReleased: {
                            const delta = screenRect.offset;
                            screenRect.offset = Qt.point(0, 0);
                            if (Math.abs(delta.x) + Math.abs(delta.y) < 3) return;
                            pane.place(screenRect.index,
                                Math.max(-65536, Math.min(65536, Math.round(screenRect.modelData.x + delta.x / canvas.factor))),
                                Math.max(-65536, Math.min(65536, Math.round(screenRect.modelData.y + delta.y / canvas.factor))));
                        }
                    }
                }
            }
        }
        FieldLabel { text: "Drag a display to move it. X and Y set its exact position." }
        RowLayout {
            Layout.fillWidth: true
            Heading {
                Layout.fillWidth: false
                text: "Editing"
            }
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
        FieldLabel { text: "Display mode" }
        Picker {
            objectName: "displays-mirror"
            Accessible.name: "Mirroring"
            enabled: pane.output?.enabled ?? false
            model: pane.mirrorChoices.map(item => item.label)
            currentIndex: Math.max(0, pane.mirrorChoices.findIndex(item => item.key === (pane.output?.mirror_of ?? "")))
            onActivated: index => pane.update(pane.selected, {mirror_of:pane.mirrorChoices[index].key || null})
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

    RowLayout {
        id: footerActions
        parent: pane.footerHost ?? pane
        width: pane.footerHost ? pane.footerHost.width : implicitWidth
        height: pane.footerHost ? pane.footerHost.height : implicitHeight
        Layout.fillWidth: true
        visible: pane.footerVisible
        ChoiceButton {
            objectName: "displays-revert"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: pane.testing
            style: pane.style
            label: "Revert"
            filled: true
            onTriggered: { pane.forceActiveFocus(); pane.service.revert(); }
        }
        ChoiceButton {
            objectName: "displays-confirm"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: pane.testing
            style: pane.style
            tone: "primary"
            label: "Keep changes"
            available: pane.service.verified
            onTriggered: { pane.forceActiveFocus(); pane.service.confirm(); }
        }
        FieldLabel {
            visible: !pane.testing
            text: pane.outcome || (pane.changes.length ? "Unsaved changes" : pane.busy ? "Working…" : "Current layout")
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
            objectName: "displays-test"
            Layout.preferredWidth: 116
            visible: !pane.testing
            style: pane.style
            label: "Test layout"
            tone: "primary"
            available: !pane.busy && pane.validLayout && pane.changes.length > 0 && !pane.invalidNumbers
            onTriggered: pane.service.previewEditor(pane.draft)
        }
    }
}
