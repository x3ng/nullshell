pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

ColumnLayout {
    id: pane
    required property Theme style
    required property var appearance
    property bool editingFixed: false
    property string inputError: ""
    readonly property bool fixed: editingFixed || appearance.effectiveSettings.location === "fixed"
    spacing: 14
    function nextTime(timestamp) {
        return timestamp ? new Date(timestamp * 1000).toLocaleString(Qt.locale(), "ddd hh:mm") : "";
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [{key: "light", label: "Light", icon: "brightness"},
                {key: "dark", label: "Dark", icon: "moon"}, {key: "auto", label: "Automatic", icon: "clock"}]
            ChoiceButton {
                required property var modelData
                objectName: "appearance-mode-" + modelData.key
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 40
                style: pane.style
                label: modelData.label
                iconKind: modelData.icon
                filled: true
                selected: pane.appearance.selectedMode === modelData.key
                available: pane.appearance.appearanceAvailable
                onTriggered: pane.appearance.selectMode(modelData.key)
            }
        }
    }
    Text {
        Layout.fillWidth: true
        text: pane.appearance.automatic
            ? "Follow sunrise and sunset · " + (pane.appearance.darkMode ? "Dark now" : "Light now")
            : "Always use " + (pane.appearance.darkMode ? "dark" : "light") + " appearance"
        wrapMode: Text.Wrap
        color: pane.style.textSecondary
        font.family: pane.style.fontFamily
        font.pixelSize: 13
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: pane.appearance.automatic
        spacing: 12
        Text {
            Layout.fillWidth: true
            text: pane.appearance.overrideUntil > 0
                ? "Temporary override until " + pane.nextTime(pane.appearance.overrideUntil)
                : pane.appearance.nextTransition ? "Next change · " + pane.nextTime(pane.appearance.nextTransition)
                : pane.appearance.locationStatus === "locating" ? "Finding approximate location…"
                : pane.appearance.locationStatus === "unavailable" ? "Location unavailable · keeping current appearance"
                : "No sunrise or sunset expected in the next two days"
            wrapMode: Text.Wrap
            color: pane.style.textSecondary
            font.family: pane.style.fontFamily
            font.pixelSize: 13
        }
        ChoiceButton {
            objectName: "appearance-resume"
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            visible: pane.appearance.overrideUntil > 0
            style: pane.style
            label: "Resume automatic"
            filled: true
            onTriggered: pane.appearance.resumeAutomatic()
        }
        Text {
            text: "Location"
            color: pane.style.textPrimary
            font.family: pane.style.fontFamily
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ChoiceButton {
                objectName: "appearance-device-location"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 36
                style: pane.style
                label: "Device location"
                filled: true
                selected: !pane.fixed
                onTriggered: { pane.editingFixed = false; pane.inputError = ""; pane.appearance.useDeviceLocation(); }
            }
            ChoiceButton {
                objectName: "appearance-fixed-location"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 36
                style: pane.style
                label: "Fixed coordinates"
                filled: true
                selected: pane.fixed
                onTriggered: { pane.editingFixed = true; pane.inputError = ""; }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: pane.fixed
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: ["latitude", "longitude"]
                    ColumnLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 5
                        Text {
                            text: parent.modelData === "latitude" ? "Latitude (−90 to 90)" : "Longitude (−180 to 180)"
                            font.family: pane.style.fontFamily
                            font.pixelSize: 12
                            color: pane.style.textSecondary
                        }
                        TextField {
                            id: field
                            objectName: "appearance-" + parent.modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            property string coordinate: parent.modelData
                            text: pane.appearance.effectiveSettings[coordinate] === null ? "" : String(pane.appearance.effectiveSettings[coordinate])
                            placeholderText: coordinate === "latitude" ? "e.g. 51.5" : "e.g. -0.1"
                            color: pane.style.textPrimary
                            placeholderTextColor: pane.style.textMuted
                            selectionColor: pane.style.surfaceSelected
                            font.family: pane.style.fontFamily
                            font.pixelSize: 14
                            selectByMouse: true
                            Accessible.name: coordinate
                            onTextEdited: { pane.inputError = ""; pane.coordinateDraft[coordinate] = text; }
                            onTextChanged: pane.coordinateDraft[coordinate] = text
                            background: Rectangle {
                                color: pane.style.inputSurface
                                radius: pane.style.radiusControl
                                border.width: 1
                                border.color: field.activeFocus ? pane.style.accent : pane.style.outline
                            }
                        }
                    }
                }
            }
            ChoiceButton {
                objectName: "appearance-apply-location"
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                style: pane.style
                label: "Apply coordinates"
                filled: true
                onTriggered: {
                    const lat = pane.coordinateDraft.latitude.trim();
                    const lon = pane.coordinateDraft.longitude.trim();
                    if (!lat || !lon || !pane.appearance.useFixedLocation(Number(lat), Number(lon))) {
                        pane.inputError = "Enter valid latitude and longitude.";
                    } else { pane.editingFixed = false; pane.inputError = ""; }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: !pane.fixed
            text: pane.appearance.locationStatus === "ready" ? "Approximate location available"
                : pane.appearance.locationStatus === "locating" ? "Requesting an approximate location…"
                : "No location available. Try again or use fixed coordinates."
            wrapMode: Text.Wrap
            color: pane.style.textSecondary
            font.family: pane.style.fontFamily
            font.pixelSize: 13
        }
        ChoiceButton {
            objectName: "appearance-retry-location"
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            visible: !pane.fixed && pane.appearance.locationStatus !== "locating"
            style: pane.style
            label: "Refresh location"
            filled: true
            onTriggered: pane.appearance.refreshLocation()
        }
    }
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: pane.inputError || pane.appearance.appearanceError
        wrapMode: Text.Wrap
        color: pane.style.danger
        font.family: pane.style.fontFamily
        font.pixelSize: 13
    }
    ChoiceButton {
        objectName: "appearance-reset"
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        visible: pane.appearance.preferencesOverridden
        style: pane.style
        label: "Use configuration defaults"
        onTriggered: { pane.editingFixed = false; pane.appearance.resetPreferences(); }
    }
    property var coordinateDraft: ({latitude: "", longitude: ""})
}
