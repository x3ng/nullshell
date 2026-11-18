pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

ColumnLayout {
    id: pane
    objectName: "shortcut-list"
    required property Theme style
    required property var source
    readonly property var matches: {
        const terms = filter.text.toLowerCase().trim().split(/\s+/);
        return source.rows.filter(row => {
            const text = [row.chord, row.description, row.dispatcher].join(" ").toLowerCase();
            return terms.every(term => text.includes(term));
        });
    }
    readonly property real naturalHeight: filter.implicitHeight + spacing + Math.max(48, Math.min(360, matches.length * 48))
    Component.onCompleted: source.refresh()
    ConnectionField {
        id: filter
        objectName: "shortcut-filter"
        Layout.fillWidth: true
        style: pane.style
        placeholderText: "Filter keyboard shortcuts"
    }
    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        Layout.preferredHeight: Math.max(48, Math.min(360, pane.matches.length * 48))
        clip: true
        model: pane.matches
        delegate: Column {
            required property var modelData
            width: ListView.view.width
            height: 48
            spacing: 2
            Text {
                width: parent.width
                text: parent.modelData.chord
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: pane.style.textPrimary
                font.family: pane.style.fontFamily
                font.pixelSize: pane.style.fontSizeBody
            }
            Text {
                width: parent.width
                text: parent.modelData.description
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: pane.style.textMuted
                font.family: pane.style.fontFamily
                font.pixelSize: pane.style.fontSizeSmall
            }
        }
        Text {
            visible: !pane.matches.length
            text: pane.source.status || "No matching shortcuts"
            color: pane.style.textMuted
            font.family: pane.style.fontFamily
        }
    }
}
