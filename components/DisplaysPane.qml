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
    property var draft: []
    property int selected: 0
    property int seconds: 0
    property string fieldError: ""
    property string lastPhase: "idle"
    readonly property var output: draft[selected] ?? null
    readonly property var details: service.editorOutputs.find(item => item.name === output?.name)
    readonly property bool busy: service.phase !== "idle"
    readonly property bool testing: service.phase === "preview"
    readonly property var independent: draft.filter(item => item.enabled && !item.mirror_of)
    readonly property bool validLayout: independent.length > 0 && draft.every(item =>
        !item.enabled || !item.mirror_of || independent.some(source => source.key === item.mirror_of))
    readonly property var modes: [...new Set([...(details?.modes ?? []), output && output.width > 0
        ? output.width + "x" + output.height + "@" + Number(output.refresh).toFixed(2) + "Hz" : ""].filter(Boolean))]
    readonly property var mirrorChoices: [{label:"Extend desktop", key:""}].concat(independent
        .filter(item => item.name !== output?.name).map(item => ({label:"Mirror " + item.name, key:item.key})))
    readonly property var orientations: ["Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]
    spacing: style.spaceSm

    function reset() {
        const name = output?.name;
        draft = service.editorOutputs.map(item => Object.assign({}, item.current));
        selected = Math.max(0, draft.findIndex(item => item.name === name));
        fieldError = "";
    }
    function update(index, fields) {
        if (!draft[index] || busy) return;
        const items = draft.slice();
        items[index] = Object.assign({}, items[index], fields);
        draft = items;
        fieldError = "";
    }
    function setMode(value) {
        const match = /^(\d+)x(\d+)@(\d+(?:\.\d+)?)(?:Hz)?$/.exec(value);
        if (match) update(selected, {width:Number(match[1]), height:Number(match[2]), refresh:Number(match[3])});
    }
    function toggleOutput() {
        const enable = !output.enabled;
        if (enable && !output.width && modes.length) setMode(modes[0]);
        update(selected, {enabled:enable});
    }
    function number(field, text) {
        const n = Number(text.trim());
        if (!text.trim() || !Number.isFinite(n) || (field === "scale"
            ? n < 0.25 || n > 8 : !Number.isInteger(n) || Math.abs(n) > 65536)) {
            fieldError = field === "scale" ? "Scale must be between 0.25 and 8." : "Enter a whole-number position.";
            return;
        }
        if (output[field] !== n) update(selected, {[field]: n});
    }
    function layoutWidth(o) { return (o.transform % 2 ? o.height : o.width) / Math.max(0.25, o.scale); }
    function layoutHeight(o) { return (o.transform % 2 ? o.width : o.height) / Math.max(0.25, o.scale); }

    Component.onCompleted: { reset(); service.refreshEditor(); }
    Connections {
        target: pane.service
        function onEditorOutputsChanged() { pane.reset(); }
        function onEditorTopologyChanged() { pane.service.refreshEditor(); }
        function onPhaseChanged() {
            if (pane.service.phase === "idle" && ["confirm", "revert"].includes(pane.lastPhase)) pane.service.refreshEditor();
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

    LabelText { visible: !pane.service.enabled; text: "Enable display editing in nullshell’s configuration to use this page." }
    LabelText { visible: pane.service.editorLoading && !pane.draft.length; text: "Reading connected displays…" }
    LabelText { visible: !!(pane.service.editorError || pane.service.error || pane.fieldError); text: pane.fieldError || pane.service.editorError || pane.service.error }

    ColumnLayout {
        Layout.fillWidth: true
        visible: pane.testing
        spacing: pane.style.spaceSm
        LabelText {
            text: pane.service.verified ? "Keep this layout? Reverting in " + pane.seconds + " s."
                                         : "Checking the new display layout…"
        }
        RowLayout {
            Layout.fillWidth: true
            ChoiceButton {
                objectName: "displays-revert"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                style: pane.style
                label: "Revert"
                onTriggered: pane.service.revert()
            }
            ChoiceButton {
                objectName: "displays-confirm"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                style: pane.style
                filled: true
                label: "Keep changes"
                available: pane.service.verified
                onTriggered: pane.service.confirm()
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: pane.service.enabled && !!pane.output && !pane.testing
        enabled: !pane.busy
        spacing: pane.style.spaceSm

        Rectangle {
            id: canvas
            Layout.fillWidth: true
            Layout.preferredHeight: 135
            radius: pane.style.radiusControl
            color: pane.style.panelSurface
            border.color: pane.style.separator
            border.width: 1
            clip: true
            readonly property var screens: pane.independent.filter(o => o.width > 0 && o.height > 0)
            readonly property real leftEdge: Math.min(...screens.map(o => o.x), 0)
            readonly property real topEdge: Math.min(...screens.map(o => o.y), 0)
            readonly property real rightEdge: Math.max(...screens.map(o => o.x + pane.layoutWidth(o)), 1)
            readonly property real bottomEdge: Math.max(...screens.map(o => o.y + pane.layoutHeight(o)), 1)
            readonly property real factor: Math.max(0.001, Math.min((width - 20) / (rightEdge - leftEdge), (height - 20) / (bottomEdge - topEdge)))
            Repeater {
                model: pane.draft
                Rectangle {
                    id: screenRect
                    required property var modelData
                    required property int index
                    property point offset: Qt.point(0, 0)
                    visible: modelData.enabled && !modelData.mirror_of
                    x: 10 + (modelData.x - canvas.leftEdge) * canvas.factor + offset.x
                    y: 10 + (modelData.y - canvas.topEdge) * canvas.factor + offset.y
                    width: Math.max(8, pane.layoutWidth(modelData) * canvas.factor)
                    height: Math.max(8, pane.layoutHeight(modelData) * canvas.factor)
                    radius: 5
                    color: pane.selected === index ? pane.style.surfaceSelected : pane.style.panelSurface
                    border.color: pane.selected === index ? pane.style.accent : pane.style.separator
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
                    }
                    MouseArea {
                        id: dragScreen
                        anchors.fill: parent
                        property point origin
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
                            pane.update(screenRect.index, {
                                x: Math.max(-65536, Math.min(65536, Math.round(screenRect.modelData.x + delta.x / canvas.factor))),
                                y: Math.max(-65536, Math.min(65536, Math.round(screenRect.modelData.y + delta.y / canvas.factor)))
                            });
                        }
                    }
                }
            }
        }
        LabelText { text: "Drag screens to arrange them, or enter a position below." }
        RowLayout {
            Layout.fillWidth: true
            Picker {
                objectName: "displays-output"
                Accessible.name: "Display"
                model: pane.draft.map(item => item.name)
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
            Picker {
                objectName: "displays-mode"
                Accessible.name: "Resolution and refresh rate"
                model: pane.modes
                currentIndex: Math.max(0, pane.modes.findIndex(value => {
                    const m = /^(\d+)x(\d+)@([\d.]+)/.exec(value);
                    return m && Number(m[1]) === pane.output?.width && Number(m[2]) === pane.output?.height
                        && Math.abs(Number(m[3]) - pane.output.refresh) < 0.015;
                }))
                onActivated: index => pane.setMode(pane.modes[index])
            }
            Picker {
                objectName: "displays-orientation"
                Accessible.name: "Orientation"
                model: pane.orientations
                currentIndex: pane.output?.transform ?? 0
                onActivated: index => pane.update(pane.selected, {transform:index})
            }
        }
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
                    LabelText { text: fieldGroup.modelData.label }
                    ConnectionField {
                        objectName: "displays-" + fieldGroup.modelData.key
                        Layout.fillWidth: true
                        style: pane.style
                        text: String(pane.output?.[fieldGroup.modelData.key] ?? "")
                        Accessible.name: fieldGroup.modelData.label
                        onEditingFinished: pane.number(fieldGroup.modelData.key, text)
                    }
                }
            }
        }
        LabelText { visible: !pane.validLayout; text: "Keep at least one independent display enabled and a valid source for every mirror." }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: pane.service.enabled && !pane.testing
        ChoiceButton {
            objectName: "displays-refresh"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            style: pane.style
            label: "Refresh"
            available: !pane.busy && !pane.service.editorLoading
            onTriggered: pane.service.refreshEditor()
        }
        ChoiceButton {
            objectName: "displays-test"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            style: pane.style
            label: "Test layout"
            filled: true
            available: !pane.busy && pane.validLayout && pane.draft.length > 0 && !pane.fieldError
            onTriggered: pane.service.previewEditor(pane.draft)
        }
    }
}
