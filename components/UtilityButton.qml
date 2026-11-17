import QtQuick
import ".."

// Icon actions share focus, input, hover and tooltip behavior with other choices.
// Keep toggle accessibility explicit at the usage boundary.
ChoiceButton {
    property bool checkable: false
    implicitHeight: 36
    iconSize: 20
    tone: "toggle"
    Accessible.role: checkable ? Accessible.CheckBox : Accessible.Button
    Accessible.checkable: checkable
    Accessible.checked: selected
}
