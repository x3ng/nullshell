import QtQuick
import "components"
import Quickshell

Item {
    id: root
    required property var theme
    property bool transparentBackground: false
    property real cardOpacity: root.frosted ? root.theme.frostedOpacity : 1
    property bool frosted: false
    property string userName: ""
    property bool editableUser: false
    property string message: ""
    property bool busy: false
    property string batteryText: ""
    property bool batteryLow: false
    property string keyboardLayout: ""
    property bool capsLock: false
    property bool revealPassword: false
    signal keyboardStatusRequested()
    signal dismissMessageRequested()
    property var sessions: []
    property string selectedSessionId: ""
    property bool sessionPickerOpen: false
    property bool showPowerActions: false
    property bool powerMenuOpen: false
    property string pendingPowerAction: ""
    signal submit(string userName, string secret)
    signal selectSession(string id)
    signal powerRequested(string action)

    readonly property var powerActions: [
        {id: "suspend", label: "Sleep", confirmLabel: "Press again to sleep", icon: "moon", danger: false},
        {id: "reboot", label: "Restart", confirmLabel: "Confirm restart", icon: "restart", danger: false},
        {id: "poweroff", label: "Shut down", confirmLabel: "Confirm shut down", icon: "power", danger: true}
    ]

    function closePowerMenu() {
        powerMenuOpen = false;
        pendingPowerAction = "";
        Qt.callLater(focusInput);
    }

    function openPowerMenu() {
        sessionPickerOpen = false;
        pendingPowerAction = "";
        powerMenuOpen = true;
        Qt.callLater(() => {
            if (powerRepeater.count > 0) powerRepeater.itemAt(0)?.forceActiveFocus();
            else powerBackButton.forceActiveFocus();
        });
    }

    function requestPower(action) {
        if (pendingPowerAction === action) {
            pendingPowerAction = "";
            powerMenuOpen = false;
            powerRequested(action);
        } else {
            pendingPowerAction = action;
            powerConfirmTimeout.restart();
        }
    }

    readonly property string selectedSessionName: {
        const entry = sessions.find(session => session.id === selectedSessionId);
        return entry ? entry.name : "Choose a session";
    }

    function clearSecret() {
        passwordInput.text = "";
        revealPassword = false;
    }

    function focusInput() {
        keyboardStatusRequested();
        if (powerMenuOpen) return;
        if (editableUser && !userInput.text.trim()) userInput.forceActiveFocus();
        else passwordInput.forceActiveFocus();
    }

    Keys.onReleased: event => {
        if (event.key === Qt.Key_CapsLock) keyboardStatusRequested();
        event.accepted = false;
    }

    Keys.onEscapePressed: {
        if (root.powerMenuOpen) {
            root.closePowerMenu();
        } else if (root.sessionPickerOpen) {
            root.sessionPickerOpen = false;
            passwordInput.forceActiveFocus();
        } else if (passwordInput.text.length > 0) {
            root.clearSecret();
            root.dismissMessageRequested();
        } else if (root.message !== "") {
            root.dismissMessageRequested();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.transparentBackground ? "transparent" : root.theme.panelSurface
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(root.width - 40, 420)
        spacing: 20

        MaterialSurface {
            materialTheme: root.theme
            frosted: root.frosted
            materialOpacity: root.cardOpacity
            shadowEnabled: true
            width: parent.width
            height: (root.powerMenuOpen ? powerPage.implicitHeight : form.implicitHeight) + 48
            radius: root.theme.radiusPanel
            border.width: 1
            border.color: root.theme.materialEdge

            Column {
                id: form
                x: 24
                y: 24
                width: parent.width - 48
                spacing: 14
                visible: !root.powerMenuOpen

                // Header: clock & date on the left; power button (greeter) or user badge (lock) on the right.
                Item {
                    width: parent.width
                    height: 36

                    Row {
                        id: timeHeader
                        height: parent.height
                        anchors.left: parent.left
                        spacing: 10

                        Text {
                            id: clockText
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.theme.textPrimary
                            font.family: root.theme.fontFamily
                            font.pixelSize: 26
                            font.weight: Font.Bold
                            text: Qt.formatDateTime(clock.date, "HH:mm")
                        }

                        Text {
                            id: dateText
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 2
                            width: Math.max(0, Math.min(implicitWidth,
                                form.width - clockText.width - 10 - headerRight.width - 12))
                            elide: Text.ElideRight
                            color: root.theme.textSecondary
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeSmall
                            font.weight: Font.Medium
                            text: Qt.formatDateTime(clock.date, "ddd, MMM d")
                        }
                    }

                    Row {
                        id: headerRight
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        // Lock screen: clean read-only user pill instead of a fake disabled input box.
                        Rectangle {
                            visible: !root.editableUser && root.userName !== ""
                            height: 28
                            width: Math.min(180, lockUserRow.implicitWidth + 16)
                            anchors.verticalCenter: parent.verticalCenter
                            radius: root.theme.radiusControl
                            color: root.theme.controlSurface

                            Row {
                                id: lockUserRow
                                anchors.centerIn: parent
                                spacing: 6

                                StatusIcon {
                                    kind: "user"
                                    width: 14
                                    height: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    ink: root.theme.accent
                                }

                                Text {
                                    text: root.userName
                                    textFormat: Text.PlainText
                                    width: Math.min(implicitWidth, 136)
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.theme.textPrimary
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.fontSizeLabel
                                    font.weight: Font.DemiBold
                                }
                            }
                        }

                        Rectangle {
                            id: powerTrigger
                            width: 34
                            height: 34
                            anchors.verticalCenter: parent.verticalCenter
                            radius: root.theme.radiusControl
                            visible: root.showPowerActions
                            color: powerMouse.containsMouse ? root.theme.surfaceHover : root.theme.controlSurface
                            border.width: activeFocus ? root.theme.focusWidth : 0
                            border.color: root.theme.focusInk
                            activeFocusOnTab: visible
                            Accessible.role: Accessible.Button
                            Accessible.name: "Power options"
                            Keys.onReturnPressed: root.openPowerMenu()
                            Keys.onEnterPressed: root.openPowerMenu()
                            Keys.onSpacePressed: root.openPowerMenu()

                            StatusIcon {
                                anchors.centerIn: parent
                                width: 16
                                height: 16
                                kind: "power"
                                ink: powerMouse.containsMouse || powerTrigger.activeFocus
                                    ? root.theme.textPrimary : root.theme.textSecondary
                            }

                            MouseArea {
                                id: powerMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openPowerMenu()
                            }
                        }
                    }
                }

                // Editable username field (Greeter only).
                Rectangle {
                    visible: root.editableUser
                    width: parent.width
                    height: 44
                    radius: root.theme.radiusInput
                    color: root.theme.inputSurface
                    border.width: userInput.activeFocus ? root.theme.focusWidth : 1
                    border.color: userInput.activeFocus ? root.theme.focusInk : root.theme.fieldOutline

                    StatusIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        kind: "user"
                        ink: userInput.activeFocus ? root.theme.accent : root.theme.textMuted
                    }

                    TextInput {
                        id: userInput
                        anchors.left: parent.left
                        anchors.leftMargin: 38
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.theme.textPrimary
                        selectionColor: root.theme.surfaceSelected
                        selectedTextColor: root.theme.textSelected
                        font.family: root.theme.fontFamily
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        text: root.userName
                        readOnly: !root.editableUser
                        activeFocusOnPress: root.editableUser
                        activeFocusOnTab: root.editableUser
                        selectByMouse: root.editableUser
                        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                        clip: true
                        enabled: !root.busy
                        onAccepted: passwordInput.forceActiveFocus()

                        Text {
                            visible: !userInput.text.length
                            text: "Username"
                            color: root.theme.textMuted
                            font: userInput.font
                        }
                    }
                }

                // Password field with show/hide toggle and vector submit button.
                Rectangle {
                    width: parent.width
                    height: 46
                    radius: root.theme.radiusInput
                    color: root.theme.inputSurface
                    border.color: passwordInput.activeFocus ? root.theme.focusInk : root.theme.fieldOutline
                    border.width: passwordInput.activeFocus ? root.theme.focusWidth : 1

                    StatusIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        kind: "lock"
                        ink: passwordInput.activeFocus ? root.theme.accent : root.theme.textMuted
                    }

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.leftMargin: 38
                        anchors.rightMargin: eyeButton.visible ? 78 : 48
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.textPrimary
                        selectionColor: root.theme.surfaceSelected
                        selectedTextColor: root.theme.textSelected
                        font.family: root.theme.fontFamily
                        font.pixelSize: 15
                        echoMode: root.revealPassword ? TextInput.Normal : TextInput.Password
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
                        selectByMouse: true
                        clip: true
                        enabled: !root.busy
                        onTextChanged: if (!text.length) root.revealPassword = false
                        onAccepted: {
                            const user = root.editableUser ? userInput.text.trim() : root.userName;
                            root.revealPassword = false;
                            root.submit(user, text);
                        }

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: 15
                            visible: passwordInput.text.length === 0
                            text: "Password"
                        }
                    }

                    Rectangle {
                        id: eyeButton
                        visible: passwordInput.text.length > 0 && !root.busy
                        anchors.right: submitButton.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 30
                        radius: root.theme.radiusSmall
                        color: eyeArea.containsMouse ? root.theme.surfaceHover : "transparent"
                        Accessible.role: Accessible.Button
                        Accessible.name: root.revealPassword ? "Hide password" : "Show password"

                        StatusIcon {
                            anchors.centerIn: parent
                            width: 15
                            height: 15
                            kind: "eye"
                            muted: root.revealPassword
                            ink: eyeArea.containsMouse ? root.theme.textPrimary : root.theme.textMuted
                        }

                        MouseArea {
                            id: eyeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.revealPassword = !root.revealPassword;
                                passwordInput.forceActiveFocus();
                            }
                        }
                    }

                    Rectangle {
                        id: submitButton
                        readonly property bool emphasized: passwordInput.text.length > 0 || submitArea.containsMouse || activeFocus
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        radius: root.theme.radiusControl
                        color: emphasized ? root.theme.accent : root.theme.controlSurface
                        border.width: activeFocus ? root.theme.focusWidth : 0
                        border.color: emphasized ? root.theme.accentInk : root.theme.focusInk
                        opacity: root.busy ? 0.55 : 1
                        activeFocusOnTab: !root.busy
                        Accessible.role: Accessible.Button
                        Accessible.name: root.editableUser ? "Sign in" : "Unlock"
                        function activate() {
                            if (root.busy) return;
                            const user = root.editableUser ? userInput.text.trim() : root.userName;
                            root.revealPassword = false;
                            root.submit(user, passwordInput.text);
                        }
                        Accessible.onPressAction: activate()
                        Keys.onReturnPressed: activate()
                        Keys.onEnterPressed: activate()
                        Keys.onSpacePressed: activate()

                        StatusIcon {
                            visible: !root.busy
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            strokeWidth: 1.7
                            kind: "arrow-right"
                            ink: submitButton.emphasized ? root.theme.accentInk : root.theme.textSecondary
                        }

                        Text {
                            visible: root.busy
                            anchors.centerIn: parent
                            text: "…"
                            font.family: root.theme.fontFamily
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: submitButton.emphasized ? root.theme.accentInk : root.theme.textSecondary
                        }

                        MouseArea {
                            id: submitArea
                            anchors.fill: parent
                            enabled: !root.busy
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: submitButton.activate()
                        }
                    }
                }

                // Caps Lock warning with icon.
                Row {
                    objectName: "login-caps-warning"
                    width: parent.width
                    spacing: 6
                    visible: root.capsLock

                    StatusIcon {
                        kind: "warning"
                        width: 15
                        height: 15
                        anchors.verticalCenter: parent.verticalCenter
                        ink: root.theme.accentWarm
                    }

                    Text {
                        text: "Caps Lock is on"
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.theme.accentWarm
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSizeSmall
                        font.weight: Font.Medium
                    }
                }

                // Keyboard-accessible Wayland session picker (Greeter only).
                Column {
                    width: parent.width
                    spacing: 6
                    visible: root.sessions.length > 0

                    Rectangle {
                        id: sessionButton
                        width: parent.width
                        height: 36
                        radius: root.theme.radiusControl
                        color: sessionMouse.containsMouse ? root.theme.surfaceHover : root.theme.controlSurface
                        border.width: activeFocus ? root.theme.focusWidth : 0
                        border.color: root.theme.focusInk
                        activeFocusOnTab: visible && !root.busy
                        Accessible.role: Accessible.ComboBox
                        Accessible.name: "Session: " + root.selectedSessionName
                        function togglePicker() {
                            if (root.busy) return;
                            root.sessionPickerOpen = !root.sessionPickerOpen;
                            if (root.sessionPickerOpen && sessionRepeater.count > 0) {
                                const idx = Math.max(0, root.sessions.findIndex(s => s.id === root.selectedSessionId));
                                Qt.callLater(() => sessionRepeater.itemAt(idx)?.forceActiveFocus());
                            }
                        }
                        Keys.onReturnPressed: togglePicker()
                        Keys.onEnterPressed: togglePicker()
                        Keys.onSpacePressed: togglePicker()
                        Keys.onDownPressed: if (!root.sessionPickerOpen) togglePicker()

                        StatusIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: 11
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15
                            height: 15
                            kind: "display"
                            ink: root.theme.textMuted
                        }

                        Text {
                            id: sessionLabel
                            anchors.left: parent.left
                            anchors.leftMargin: 34
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Session"
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeSmall
                        }

                        Text {
                            anchors.left: sessionLabel.right
                            anchors.leftMargin: 10
                            anchors.right: sessionChevron.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: root.selectedSessionName
                            color: root.theme.textPrimary
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeSmall
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        StatusIcon {
                            id: sessionChevron
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15
                            height: 15
                            kind: "chevron-down"
                            rotation: root.sessionPickerOpen ? 180 : 0
                            ink: root.theme.textSecondary
                        }

                        MouseArea {
                            id: sessionMouse
                            anchors.fill: parent
                            enabled: !root.busy
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sessionButton.togglePicker()
                        }
                    }

                    Flickable {
                        width: parent.width
                        height: root.sessionPickerOpen ? Math.min(sessionOptions.height, 168) : 0
                        contentWidth: width
                        contentHeight: sessionOptions.height
                        clip: true
                        visible: root.sessionPickerOpen

                        Column {
                            id: sessionOptions
                            width: parent.width
                            spacing: 4

                            Repeater {
                                id: sessionRepeater
                                model: root.sessions
                                delegate: Rectangle {
                                    id: optionRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool currentOption: modelData.id === root.selectedSessionId
                                    width: sessionOptions.width
                                    height: 36
                                    radius: root.theme.radiusControl
                                    color: currentOption
                                        ? (optionMouse.containsMouse ? root.theme.surfaceSelectedHover : root.theme.surfaceSelected)
                                        : (optionMouse.containsMouse ? root.theme.surfaceHover : root.theme.controlSurface)
                                    border.width: activeFocus ? root.theme.focusWidth : 0
                                    border.color: root.theme.focusInk
                                    activeFocusOnTab: root.sessionPickerOpen
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: modelData.name
                                    function chooseOption() {
                                        root.selectSession(optionRow.modelData.id);
                                        root.sessionPickerOpen = false;
                                        passwordInput.forceActiveFocus();
                                    }
                                    Keys.onReturnPressed: chooseOption()
                                    Keys.onEnterPressed: chooseOption()
                                    Keys.onSpacePressed: chooseOption()
                                    Keys.onUpPressed: if (index > 0) sessionRepeater.itemAt(index - 1)?.forceActiveFocus()
                                    Keys.onDownPressed: if (index + 1 < sessionRepeater.count) sessionRepeater.itemAt(index + 1)?.forceActiveFocus()

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.right: selectedMark.left
                                        anchors.rightMargin: 8
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: optionRow.modelData.name
                                        color: root.theme.textPrimary
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.fontSizeSmall
                                        font.weight: optionRow.currentOption ? Font.DemiBold : Font.Normal
                                    }

                                    StatusIcon {
                                        id: selectedMark
                                        visible: optionRow.currentOption
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 14
                                        height: 14
                                        kind: "check"
                                        ink: root.theme.accent
                                    }

                                    MouseArea {
                                        id: optionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: optionRow.chooseOption()
                                    }
                                }
                            }
                        }
                    }
                }

                // Authentication / session message.
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    visible: text.length > 0
                    color: /fail|error|unavailable|invalid|enter a/i.test(root.message)
                        ? root.theme.danger : root.theme.accentWarm
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSizeSmall
                    font.weight: Font.Medium
                    text: root.message
                    textFormat: Text.PlainText
                }

                // Bottom status rail (battery & keyboard layout).
                Item {
                    id: statusLine
                    width: parent.width
                    visible: root.batteryText !== "" || root.keyboardLayout !== ""
                    height: Math.max(chargeRow.visible ? chargeRow.implicitHeight : 0,
                        layoutInfo.visible ? layoutInfo.height : 0)

                    Row {
                        id: chargeRow
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.batteryText !== ""
                        spacing: 6

                        StatusIcon {
                            kind: "battery"
                            width: 15
                            height: 15
                            anchors.verticalCenter: parent.verticalCenter
                            ink: root.batteryLow ? root.theme.accentWarm : root.theme.textMuted
                        }

                        Text {
                            id: charge
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.batteryText
                            textFormat: Text.PlainText
                            color: root.batteryLow ? root.theme.accentWarm : root.theme.textSecondary
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeLabel
                        }
                    }

                    Row {
                        id: layoutInfo
                        visible: root.keyboardLayout !== ""
                        spacing: 6
                        x: chargeRow.visible ? statusLine.width - width : 0
                        anchors.verticalCenter: parent.verticalCenter

                        StatusIcon {
                            kind: "keyboard"
                            ink: root.theme.textMuted
                            width: 15
                            height: 15
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.keyboardLayout
                            textFormat: Text.PlainText
                            width: Math.min(implicitWidth, Math.max(1, statusLine.width
                                - (chargeRow.visible ? chargeRow.width + 12 : 0) - 15 - layoutInfo.spacing))
                            wrapMode: Text.Wrap
                            color: root.theme.textSecondary
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeLabel
                            Accessible.name: "Keyboard · " + text
                        }
                    }
                }
            }

            // Keyboard-accessible Greeter Power Menu (Sleep, Restart, Shut down + Back / Esc).
            Column {
                id: powerPage
                x: 24
                y: 24
                width: parent.width - 48
                spacing: 10
                visible: root.powerMenuOpen

                Item {
                    width: parent.width
                    height: 34

                    Rectangle {
                        id: powerBackButton
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: 32
                        width: backRow.implicitWidth + 18
                        radius: root.theme.radiusControl
                        color: backMouse.containsMouse ? root.theme.surfaceHover : root.theme.controlSurface
                        border.width: activeFocus ? root.theme.focusWidth : 0
                        border.color: root.theme.focusInk
                        activeFocusOnTab: root.powerMenuOpen
                        Accessible.role: Accessible.Button
                        Accessible.name: "Back to login"
                        Keys.onReturnPressed: root.closePowerMenu()
                        Keys.onEnterPressed: root.closePowerMenu()
                        Keys.onSpacePressed: root.closePowerMenu()
                        Keys.onDownPressed: if (powerRepeater.count > 0) powerRepeater.itemAt(0)?.forceActiveFocus()

                        Row {
                            id: backRow
                            anchors.centerIn: parent
                            spacing: 6

                            StatusIcon {
                                kind: "back"
                                width: 15
                                height: 15
                                anchors.verticalCenter: parent.verticalCenter
                                ink: root.theme.textSecondary
                            }

                            Text {
                                text: "Back"
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.theme.textPrimary
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fontSizeSmall
                                font.weight: Font.Medium
                            }
                        }

                        MouseArea {
                            id: backMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closePowerMenu()
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Power"
                        color: root.theme.textPrimary
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSizeTitle
                        font.weight: Font.DemiBold
                    }
                }

                Repeater {
                    id: powerRepeater
                    model: root.powerActions
                    delegate: Rectangle {
                        id: powerOption
                        required property var modelData
                        required property int index
                        readonly property bool confirming: root.pendingPowerAction === modelData.id
                        width: powerPage.width
                        height: 42
                        radius: root.theme.radiusControl
                        color: confirming
                            ? (powerOptMouse.containsMouse ? root.theme.surfaceSelectedHover : root.theme.surfaceSelected)
                            : (powerOptMouse.containsMouse ? root.theme.surfaceHover : root.theme.controlSurface)
                        border.width: activeFocus ? root.theme.focusWidth : 0
                        border.color: root.theme.focusInk
                        activeFocusOnTab: root.powerMenuOpen
                        Accessible.role: Accessible.Button
                        Accessible.name: confirming ? modelData.confirmLabel : modelData.label
                        Keys.onReturnPressed: root.requestPower(modelData.id)
                        Keys.onEnterPressed: root.requestPower(modelData.id)
                        Keys.onSpacePressed: root.requestPower(modelData.id)
                        Keys.onUpPressed: {
                            if (index > 0) powerRepeater.itemAt(index - 1)?.forceActiveFocus();
                            else powerBackButton.forceActiveFocus();
                        }
                        Keys.onDownPressed: {
                            if (index + 1 < powerRepeater.count) powerRepeater.itemAt(index + 1)?.forceActiveFocus();
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            StatusIcon {
                                kind: powerOption.modelData.icon
                                width: 17
                                height: 17
                                anchors.verticalCenter: parent.verticalCenter
                                ink: powerOption.confirming && powerOption.modelData.danger
                                    ? root.theme.danger
                                    : powerOption.confirming ? root.theme.accent : root.theme.textSecondary
                            }

                            Text {
                                text: powerOption.confirming ? powerOption.modelData.confirmLabel : powerOption.modelData.label
                                anchors.verticalCenter: parent.verticalCenter
                                color: powerOption.confirming && powerOption.modelData.danger
                                    ? root.theme.danger : root.theme.textPrimary
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fontSizeBody
                                font.weight: powerOption.confirming ? Font.DemiBold : Font.Medium
                            }
                        }

                        MouseArea {
                            id: powerOptMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.requestPower(powerOption.modelData.id)
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: powerConfirmTimeout
        interval: 5000
        onTriggered: root.pendingPowerAction = ""
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
}
