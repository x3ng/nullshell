pragma ComponentBehavior: Bound

import QtQuick

// Shared center content; activation and dismissal are owned by Notifications.
NotificationCard {
    compact: true
    expandable: !compact
    signal triggered()
    onDismissRequested: triggered()
}
