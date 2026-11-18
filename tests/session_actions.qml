import QtQuick
import Quickshell
import "."

ShellRoot {
    id: root
    property int stage: 0
    property string lockError: ""
    SessionActions { id: actions }
    function check(condition, message) {
        if (!condition) { console.error(message); Qt.exit(1); }
    }
    Connections {
        target: actions
        function onLockFailed(reason) { root.lockError = reason; }
        function onAccepted(action) {
            if (root.stage === 1) {
                root.check(action === "reboot", "Wrong reboot action");
                root.stage = 2;
                Qt.callLater(() => root.check(actions.execute("logout"), "Logout rejected"));
            } else if (root.stage === 2) {
                root.check(action === "logout", "Wrong logout action");
                root.stage = 3;
                Qt.callLater(() => root.check(actions.execute("suspend"), "Suspend rejected"));
            } else { root.check(false, "Failed action reported as accepted"); }
        }
    }
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            if (root.stage === 0 && actions.capabilities.reboot && actions.capabilities.suspend) {
                root.check(!actions.available("poweroff"), "Denied capability enabled");
                root.check(!actions.execute("unknown"), "Unknown action accepted");
                root.stage = 1;
                root.check(actions.execute("reboot"), "Reboot rejected");
                root.check(!actions.execute("logout"), "Concurrent operation accepted");
            } else if (root.stage === 3 && !actions.busy && actions.error !== "") {
                root.check(actions.error.includes("Synthetic denial"), "Failure not reported");
                root.stage = 4;
                root.check(actions.lock(), "Lock rejected");
                root.check(!actions.lock(), "Duplicate lock accepted");
            } else if (root.stage === 4 && !actions.lockPending) {
                root.check(root.lockError === (Quickshell.env("TEST_UWSM") === "yes" ? "" : "Synthetic lock failure"), "Incorrect lock feedback");
                console.log("SESSION_ACTIONS_OK");
                Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.error("Session test timed out"); Qt.exit(1); } }
}
