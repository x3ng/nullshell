import QtQuick
import QtQuick.Window

// Reveal keyboard focus without changing the scroll position for focus outside
// this body (for example, search, page actions or a detached window).
Flickable {
    id: view
    property bool followFocus: true
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function revealFocus() {
        if (!followFocus || !visible) return;
        const item = view.Window.window?.activeFocusItem;
        if (!item) return;
        let ancestor = item;
        while (ancestor && ancestor !== contentItem) ancestor = ancestor.parent;
        if (!ancestor) return;
        const top = item.mapToItem(view, 0, 0).y;
        const adjustment = top < 0 ? top : Math.max(0, top + item.height - height);
        contentY = Math.max(0, Math.min(contentY + adjustment, contentHeight - height));
    }

    Connections {
        target: view.Window.window
        enabled: view.followFocus && view.visible
        function onActiveFocusItemChanged() { Qt.callLater(view.revealFocus); }
    }
}
