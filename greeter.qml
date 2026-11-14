import QtQuick
import Quickshell
import "greeter"

// Keep greeter and its shared types inside one Quickshell scan root.
ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false
    Loader {
        source: "greeter/shell.qml"
        onStatusChanged: if (status === Loader.Error) Qt.callLater(Qt.quit)
    }
}
