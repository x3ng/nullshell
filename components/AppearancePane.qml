pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: pane
    required property Theme style
    required property var appearance
    property bool editingFixed: false
    property string inputError: ""
    readonly property bool fixed: editingFixed || appearance.effectiveSettings.location === "fixed"
    spacing: pane.style.spaceSm
    function nextTime(timestamp) {
        return timestamp ? new Date(timestamp * 1000).toLocaleString(Qt.locale(), "ddd hh:mm") : "";
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: pane.style.spaceSm
        Repeater {
            model: [{key: "light", label: "Light", icon: "brightness"},
                {key: "dark", label: "Dark", icon: "moon"}, {key: "auto", label: "Automatic", icon: "clock"}]
            ChoiceButton {
                required property var modelData
                objectName: "appearance-mode-" + modelData.key
                Layout.fillWidth: true
                Layout.preferredWidth: 1
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
        font.pixelSize: pane.style.fontSizeSmall
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: pane.appearance.automatic
        spacing: pane.style.spaceMd
        Text {
            Layout.fillWidth: true
            text: pane.appearance.overrideUntil > 0
                ? "Temporary override until " + pane.nextTime(pane.appearance.overrideUntil)
                : pane.appearance.nextTransition ? "Next change · " + pane.nextTime(pane.appearance.nextTransition)
                : pane.appearance.locationStatus === "unset" ? "Choose a location source to calculate sunrise and sunset."
                : pane.appearance.locationStatus === "locating" ? "Finding approximate location…"
                : pane.appearance.locationStatus === "unavailable" ? "Location unavailable · keeping current appearance"
                : "No sunrise or sunset expected in the next two days"
            wrapMode: Text.Wrap
            color: pane.style.textSecondary
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeSmall
        }
        ChoiceButton {
            objectName: "appearance-resume"
            Layout.fillWidth: true
            visible: pane.appearance.overrideUntil > 0
            style: pane.style
            label: "Resume automatic"
            filled: true
            onTriggered: pane.appearance.resumeAutomatic()
        }
        Text {
            Layout.topMargin: pane.style.spaceXs
            text: "Location"
            color: pane.style.textPrimary
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeBody
            font.weight: Font.Medium
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: pane.style.spaceSm
            ChoiceButton {
                objectName: "appearance-timezone-location"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                style: pane.style
                label: "Time zone"
                filled: true
                selected: !pane.fixed && pane.appearance.effectiveSettings.location === "timezone"
                onTriggered: { pane.editingFixed = false; pane.inputError = ""; pane.appearance.useTimezoneLocation(); }
            }
            ChoiceButton {
                objectName: "appearance-ip-location"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                style: pane.style
                label: "IP location"
                filled: true
                selected: !pane.fixed && pane.appearance.effectiveSettings.location === "ip"
                onTriggered: { pane.editingFixed = false; pane.inputError = ""; pane.appearance.useIpLocation(); }
            }
            ChoiceButton {
                objectName: "appearance-fixed-location"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                style: pane.style
                label: "Coordinates"
                filled: true
                selected: pane.fixed
                onTriggered: { pane.editingFixed = true; pane.inputError = ""; }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: pane.fixed
            spacing: pane.style.spaceSm
            RowLayout {
                Layout.fillWidth: true
                spacing: pane.style.spaceSm
                Repeater {
                    model: ["latitude", "longitude"]
                    ColumnLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: pane.style.spaceXs
                        Text {
                            text: parent.modelData === "latitude" ? "Latitude (−90 to 90)" : "Longitude (−180 to 180)"
                            font.family: pane.style.fontFamily
                            font.pixelSize: pane.style.fontSizeLabel
                            color: pane.style.textSecondary
                        }
                        ConnectionField {
                            style: pane.style
                            objectName: "appearance-" + parent.modelData
                            Layout.fillWidth: true
                            property string coordinate: parent.modelData
                            text: pane.appearance.effectiveSettings[coordinate] === null ? "" : String(pane.appearance.effectiveSettings[coordinate])
                            placeholderText: coordinate === "latitude" ? "e.g. 51.5" : "e.g. -0.1"
                            Accessible.name: coordinate
                            onTextEdited: { pane.inputError = ""; pane.coordinateDraft[coordinate] = text; }
                            onTextChanged: pane.coordinateDraft[coordinate] = text
                        }
                    }
                }
            }
            ChoiceButton {
                objectName: "appearance-apply-location"
                Layout.fillWidth: true
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
            text: "Time zone works offline. IP location contacts BeaconDB, which sees your public IP."
            wrapMode: Text.Wrap
            color: pane.style.textSecondary
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeSmall
        }
        Text {
            Layout.fillWidth: true
            visible: !pane.fixed
            text: pane.appearance.locationStatus === "ready"
                ? (pane.appearance.effectiveSettings.location === "timezone" ? "Using an approximate location for your time zone" : "Approximate IP location available")
                : pane.appearance.locationStatus === "locating" ? "Requesting an approximate location…"
                : "No location available. Try again or use fixed coordinates."
            wrapMode: Text.Wrap
            color: pane.style.textSecondary
            font.family: pane.style.fontFamily
            font.pixelSize: pane.style.fontSizeSmall
        }
        ChoiceButton {
            objectName: "appearance-retry-location"
            Layout.fillWidth: true
            visible: !pane.fixed && pane.appearance.effectiveSettings.location === "ip" && pane.appearance.locationStatus !== "locating"
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
        font.pixelSize: pane.style.fontSizeSmall
    }
    ChoiceButton {
        objectName: "appearance-reset"
        Layout.topMargin: pane.style.spaceSm
        Layout.fillWidth: true
        visible: pane.appearance.preferencesOverridden
        style: pane.style
        label: "Use configuration defaults"
        onTriggered: { pane.editingFixed = false; pane.appearance.resetPreferences(); }
    }
    property var coordinateDraft: ({latitude: "", longitude: ""})
}
