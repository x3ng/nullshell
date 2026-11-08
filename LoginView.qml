import QtQuick
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
    property var sessions: []
    property string selectedSessionId: ""
    property bool sessionPickerOpen: false
    property bool showPowerActions: false
    property bool powerMenuOpen: false
    property string pendingPowerAction: ""
    signal submit(string userName, string secret)
    signal selectSession(string id)
    signal powerRequested(string action)

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

    function clearSecret() { passwordInput.text = ""; }
    function focusInput() {
        if (editableUser && !userInput.text.trim()) userInput.forceActiveFocus();
        else passwordInput.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: root.transparentBackground ? "transparent" : root.theme.panelSurface
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(root.width - 40, 440)
        spacing: 24

        MaterialSurface {
            materialTheme: root.theme
            frosted: root.frosted
            materialOpacity: root.cardOpacity
            shadowEnabled: true
            width: parent.width
            height: (root.powerMenuOpen ? powerPage.implicitHeight : form.implicitHeight) + 56
            radius: root.theme.radiusPanel

            Column {
                id: form
                x: 28
                y: 28
                width: parent.width - 56
                spacing: 18
                visible: !root.powerMenuOpen

                Item {
                    width: parent.width
                    height: 40

                    Text {
                        id: clockText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.theme.textPrimary
                        font.family: root.theme.fontFamily
                        font.pixelSize: 26
                        font.weight: Font.DemiBold
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                    }

                    Text {
                        id: dateText
                        anchors.left: clockText.right
                        anchors.leftMargin: 16
                        anchors.right: root.showPowerActions ? powerTrigger.left : parent.right
                        anchors.rightMargin: 8
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.theme.textSecondary
                        font.family: root.theme.fontFamily
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        text: Qt.formatDateTime(clock.date, "ddd, d MMM")
                    }

                    Rectangle {
                        id: powerTrigger
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36; radius: root.theme.radiusControl
                        visible: root.showPowerActions
                        color: powerMouse.containsMouse || activeFocus ? root.theme.surfaceHover : "transparent"
                        activeFocusOnTab: visible
                        Accessible.role: Accessible.Button
                        Accessible.name: "Power options"
                        function activate() { root.powerMenuOpen = true; }
                        Accessible.onPressAction: activate()
                        Keys.onReturnPressed: activate()
                        Keys.onSpacePressed: activate()
                        Canvas {
                            anchors.centerIn: parent
                            width: 20; height: 20
                            readonly property color ink: root.theme.textSecondary
                            onInkChanged: requestPaint()
                            onPaint: {
                                const c = getContext("2d"); c.reset();
                                c.strokeStyle = ink; c.lineWidth = 1.8; c.lineCap = "round";
                                c.beginPath(); c.arc(10, 11, 6.5, -0.8, Math.PI + 0.8); c.stroke();
                                c.beginPath(); c.moveTo(10, 2); c.lineTo(10, 10); c.stroke();
                            }
                        }
                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: powerTrigger.activate()
                        }
                    }

                }

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: root.theme.radiusInput
                    color: root.theme.inputSurface
                    border.width: 1
                    border.color: userInput.activeFocus ? root.theme.accent : root.theme.separator

                    TextInput {
                        id: userInput
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.theme.textPrimary
                        font.family: root.theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Normal
                        text: root.userName
                        readOnly: !root.editableUser
                        activeFocusOnPress: root.editableUser
                        activeFocusOnTab: root.editableUser
                        selectByMouse: root.editableUser
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

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: root.theme.radiusInput
                    color: root.theme.inputSurface
                    border.color: passwordInput.activeFocus ? root.theme.accent : root.theme.separator
                    border.width: 1

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.margins: 14
                        anchors.rightMargin: 60
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.textPrimary
                        font.family: root.theme.fontFamily
                        font.pixelSize: 16
                        echoMode: TextInput.Password
                        enabled: !root.busy
                        onAccepted: root.submit(userInput.text.trim(), text)

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: 16
                            visible: passwordInput.text.length === 0
                            text: "Password"
                        }
                    }
                    Rectangle {
                        id: submitButton
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36; radius: root.theme.radiusControl
                        color: submitArea.containsMouse || activeFocus ? root.theme.accent : root.theme.surfaceSelected
                        opacity: root.busy ? 0.5 : 1
                        activeFocusOnTab: !root.busy
                        Accessible.role: Accessible.Button
                        Accessible.name: root.editableUser ? "Sign in" : "Unlock"
                        function activate() { if (!root.busy) root.submit(userInput.text.trim(), passwordInput.text); }
                        Accessible.onPressAction: activate()
                        Keys.onReturnPressed: activate()
                        Keys.onSpacePressed: activate()
                        Text {
                            anchors.centerIn: parent
                            text: root.busy ? "…" : "→"
                            font.family: root.theme.fontFamily
                            font.pixelSize: 22
                            color: submitArea.containsMouse || submitButton.activeFocus ? root.theme.accentInk : root.theme.textPrimary
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

                Column {
                    width: parent.width
                    spacing: 6
                    visible: root.sessions.length > 0

                    Rectangle {
                        width: parent.width
                        height: 32
                        radius: root.theme.radiusInput
                        color: "transparent"
                        border.width: 0

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Session"
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: 14
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 76
                            anchors.right: sessionArrow.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.selectedSessionName
                            color: root.theme.textPrimary
                            font.family: root.theme.fontFamily
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Text {
                            id: sessionArrow
                            anchors.right: parent.right
                            anchors.rightMargin: 2
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.sessionPickerOpen ? "⌃" : "⌄"
                            color: root.theme.textSecondary
                            font.pixelSize: 16
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.busy
                            onClicked: root.sessionPickerOpen = !root.sessionPickerOpen
                        }
                    }

                    Flickable {
                        width: parent.width
                        height: root.sessionPickerOpen ? Math.min(sessionOptions.height, 176) : 0
                        contentWidth: width
                        contentHeight: sessionOptions.height
                        clip: true
                        visible: root.sessionPickerOpen

                        Column {
                            id: sessionOptions
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: root.sessions
                                delegate: Rectangle {
                                    id: optionRow
                                    required property var modelData
                                    width: sessionOptions.width
                                    height: 42
                                    radius: root.theme.radiusInput
                                    color: optionRow.modelData.id === root.selectedSessionId
                                        ? root.theme.surfaceSelected : root.theme.panelSurface

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: optionRow.modelData.name
                                        color: root.theme.textPrimary
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: 14
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.selectSession(optionRow.modelData.id);
                                            root.sessionPickerOpen = false;
                                            passwordInput.forceActiveFocus();
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    visible: text.length > 0
                    color: root.theme.accentWarm
                    font.family: root.theme.fontFamily
                    font.pixelSize: 14
                    text: root.message
                    textFormat: Text.PlainText
                }



            }

            Column {
                id: powerPage
                x: 28
                y: 28
                width: parent.width - 56
                spacing: 18
                visible: root.powerMenuOpen

                Item {
                    width: parent.width
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "←  Back"
                        color: root.theme.textSecondary
                        font.family: root.theme.fontFamily
                        font.pixelSize: 14
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.powerMenuOpen = false;
                                root.pendingPowerAction = "";
                                root.focusInput();
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Power"
                        color: root.theme.textPrimary
                        font.family: root.theme.fontFamily
                        font.pixelSize: 16
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: root.theme.radiusInput
                    color: restartArea.containsMouse ? root.theme.surfaceHover : "transparent"
                    border.color: root.theme.outline
                    border.width: 0
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 15
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pendingPowerAction === "reboot" ? "Confirm restart" : "Restart"
                        color: root.theme.textPrimary
                        font.family: root.theme.fontFamily
                        font.pixelSize: 16
                    }
                    MouseArea {
                        id: restartArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.requestPower("reboot")
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: root.theme.radiusInput
                    color: shutdownArea.containsMouse ? root.theme.surfaceHover : "transparent"
                    border.color: root.theme.outline
                    border.width: 0
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 15
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pendingPowerAction === "poweroff" ? "Confirm shut down" : "Shut down"
                        color: root.theme.textPrimary
                        font.family: root.theme.fontFamily
                        font.pixelSize: 16
                    }
                    MouseArea {
                        id: shutdownArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.requestPower("poweroff")
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
