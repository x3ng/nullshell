import QtQuick
import QtTest
import "../components"

Item {
    id: scene
    width: 640
    height: 400

    QtObject {
        id: fixture
        readonly property var initial: [
            { name: "Center", enabled: true, width: 1920, height: 1080, x: 0, y: 0, scale: 1, transform: 0 },
            { name: "Right", enabled: true, width: 2560, height: 1440, x: 1920, y: 0, scale: 1, transform: 0 },
            { name: "Portrait", enabled: true, width: 1920, height: 1080, x: -1080, y: -280, scale: 1, transform: 1 }
        ]
        property var outputs: initial
        property int selected: -1
    }
    Flickable {
        id: viewport
        width: parent.width
        height: 225
        contentHeight: 500
        DisplayArrangement {
            id: arrangement
            width: viewport.width
            height: 184
            style: ({radiusControl: 3, radiusCard: 3, backgroundSurface: "#18191c", separator: "#43454a",
                surfaceSelected: "#383e4e", surfaceRaised: "#292c32", accent: "#8aafe6", outline: "#4a535c",
                textPrimary: "#f0f1f3", fontFamily: "sans-serif", fontSizeSmall: 13})
            outputs: fixture.outputs
            selected: fixture.selected
            onOutputSelected: index => fixture.selected = index
            onOutputMoved: (index, x, y) => {
                const outputs = fixture.outputs.slice();
                outputs[index] = Object.assign({}, outputs[index], {x, y});
                fixture.outputs = outputs;
            }
        }
    }
    TestCase {
        name: "DisplayArrangement"
        when: windowShown

        function init() {
            fixture.outputs = fixture.initial.slice();
            fixture.selected = -1;
            viewport.contentY = 0;
        }

        function test_dragInsideScrollablePage_data() {
            return [{tag: "vertical", dx: 0, dy: -32}, {tag: "horizontal", dx: 35, dy: 0}];
        }

        function test_dragInsideScrollablePage(data) {
            const tile = findChild(arrangement, "arrangement-output-Portrait");
            verify(tile !== null);
            const center = tile.mapToItem(scene, tile.width / 2, tile.height / 2);
            const factor = arrangement.factor;
            mouseDrag(scene, center.x, center.y, data.dx, data.dy, Qt.LeftButton);
            compare(fixture.selected, 2);
            verify(Math.abs(fixture.outputs[2].x - (-1080 + data.dx / factor)) < 2 / factor);
            verify(Math.abs(fixture.outputs[2].y - (-280 + data.dy / factor)) < 2 / factor);
            compare(fixture.outputs[0], fixture.initial[0]);
            compare(fixture.outputs[1], fixture.initial[1]);
            compare(viewport.contentY, 0);
        }
    }
}
