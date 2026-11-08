import QtQuick

// Update data in place so live titles do not destroy hovered delegates.
ListModel {
    id: stable
    property var rows: []
    property string keyField: "key"
    property var identities: []
    dynamicRoles: true
    onRowsChanged: reconcile()
    Component.onCompleted: reconcile()

    function reconcile() {
        const keys = identities.slice();
        for (let i = 0; i < rows.length; ++i) {
            const row = rows[i];
            const key = row[keyField];
            const previous = keys.indexOf(key, i);
            if (previous < 0) {
                insert(i, {record: row});
                keys.splice(i, 0, key);
            } else {
                if (previous !== i) {
                    move(previous, i, 1);
                    keys.splice(i, 0, keys.splice(previous, 1)[0]);
                }
                setProperty(i, "record", row);
            }
        }
        if (count > rows.length) remove(rows.length, count - rows.length);
        identities = keys.slice(0, rows.length);
    }
}
