import QtQuick
import Quickshell
import Quickshell.Io
import "components/DisplayGeometry.js" as Geometry

// Placement rules for the display editor, without a compositor or helper.
// The layout values here are synthetic vectors shared with the Rust planner.
ShellRoot {
    id: root
    property var failures: []
    property int cases: 0

    function check(name: string, condition: bool): void {
        root.cases += 1;
        if (!condition) root.failures = [...root.failures, name];
    }
    function output(changes): var {
        return Object.assign({key: changes.name, name: "", enabled: true, width: 1920, height: 1080,
            refresh: 60, x: 0, y: 0, scale: 1, transform: 0}, changes);
    }
    function issueKinds(outputs): string {
        return Geometry.issues(outputs).map(item => item.kind).join(",");
    }
    function names(outputs): string {
        return Geometry.rects(outputs).map(item => item.name).join(",");
    }

    IpcHandler {
        target: "geometry"
        function status(): string {
            return JSON.stringify({cases: root.cases, failures: root.failures});
        }
    }

    Component.onCompleted: {
        try {
            root.run();
        } catch (error) {
            root.failures = [...root.failures, "exception at case " + root.cases + ": " + error];
        }
    }

    function run(): void {
        const panel = output({name: "eDP-1"});
        const external = output({name: "DP-1", width: 2560, height: 1440});
        const third = output({name: "HDMI-A-1", x: 4480});

        // A single display is a valid layout and defines no gap.
        check("single", Geometry.valid([panel]) && Geometry.issues([panel]).length === 0);
        check("single rect", names([panel]) === "eDP-1");

        // Flush pairs are valid; a positive-length shared edge is the contact.
        check("flush", Geometry.valid([panel, output({name: "DP-1", x: 1920})]));
        check("flush rotating", Geometry.valid([output({name: "eDP-1", transform: 1}),
            output({name: "DP-1", x: 1080, width: 1920, height: 1080})]));
        check("flush scaled", Geometry.valid([output({name: "eDP-1", width: 1280, height: 720, scale: 1.25}),
            output({name: "DP-1", x: 1024, width: 1920, height: 1080})]));
        check("flush negative", Geometry.valid([panel, output({name: "DP-1", x: -2560, width: 2560, height: 1440})]));

        // L, T and bridging shapes are connected layouts, not "filled rectangles".
        check("L shape", Geometry.valid([panel, output({name: "DP-1", x: 1920, y: 540, width: 2560, height: 1440})]));
        check("bridge", Geometry.valid([panel, output({name: "DP-1", x: 1920, width: 2560, height: 1440}), third]));

        // Overlaps are rejected and named.
        const overlapping = [panel, output({name: "DP-1", x: 1900, width: 2560, height: 1440})];
        check("overlap rejected", !Geometry.valid(overlapping));
        check("overlap named", issueKinds(overlapping) === "overlap"
            && Geometry.issues(overlapping)[0].text.indexOf("DP-1") >= 0);
        check("contained overlap", !Geometry.valid([output({name: "eDP-1", width: 3840, height: 2160}),
            output({name: "DP-1", x: 100, y: 100, width: 2560, height: 1440})]));

        // A gap, a corner-only touch and a floated pair are all detached.
        check("gap rejected", !Geometry.valid([panel, output({name: "DP-1", x: 1925})]));
        check("one pixel gap", issueKinds([panel, output({name: "DP-1", x: 1921})]) === "detached");
        check("corner touch", issueKinds([panel, output({name: "DP-1", x: 1920, y: 1080})]) === "detached");
        check("floating pair", issueKinds([panel, output({name: "DP-1", x: 1920}),
            output({name: "HDMI-A-1", x: 10000})]) === "detached");
        check("detached names", Geometry.issues([panel, output({name: "DP-1", x: 1920}),
            output({name: "HDMI-A-1", x: 10000})])[0].names.join(",") === "HDMI-A-1");

        // Disabled and mirrored outputs never participate in geometry.
        check("disabled ignored", Geometry.valid([panel, output({name: "DP-1", x: 1920, enabled: false})]));
        check("mirror ignored", names([panel, output({name: "DP-1", x: 0, mirror_of: "eDP-1"})]) === "eDP-1");
        check("mirror keeps one rect", Geometry.valid([panel, output({name: "DP-1", x: 0, mirror_of: "eDP-1"})]));
        check("no mode ignored", Geometry.valid([panel, output({name: "DP-1", x: 1920, width: 0})]));

        // Snapping: a dragged display lands flush on a neighbour edge.
        const others = Geometry.rects([panel, external]);
        const neighbour = [others[0]];
        check("snap flush right", Geometry.snap(1912, 4, 2560, 1440, neighbour, {}).x === 1920);
        check("snap flush left", Geometry.snap(-2550, 0, 2560, 1440, neighbour, {}).x === -2560);
        check("snap aligns top", Geometry.snap(1920, 6, 2560, 1440, neighbour, {}).y === 0);
        check("snap reports guide", Geometry.snap(1912, 0, 2560, 1440, neighbour, {}).guideX === 1920);

        // Outside the entry threshold the position is kept, not rounded away.
        check("no snap far", Geometry.snap(2200, 900, 2560, 1440, neighbour, {}).x === 2200);
        check("threshold boundary", Geometry.snap(2200, 0, 2560, 1440, neighbour, {enter: 300}).x !== 2200);

        // Hysteresis keeps a held edge until the pointer leaves the release band.
        const band = {enter: 10, exit: 20};
        const held = Geometry.snap(1925, 0, 2560, 1440, neighbour, band);
        check("hysteresis entry", held.x === 1920);
        check("outside entry band", Geometry.snap(1935, 0, 2560, 1440, neighbour, band).x === 1935);
        check("hysteresis holds", Geometry.snap(1935, 0, 2560, 1440, neighbour,
            Object.assign({held: held}, band)).x === 1920);
        check("hysteresis releases", Geometry.snap(1945, 0, 2560, 1440, neighbour,
            Object.assign({held: held}, band)).x === 1945);
        check("slides along held edge", Geometry.snap(1930, 300, 2560, 1440, neighbour,
            Object.assign({held: held}, band)).y === 300);

        // A candidate never lands on top of another display when a legal one exists.
        const boxed = Geometry.snap(100, 0, 2560, 1440, neighbour, {enter: 4096});
        check("no overlap candidate", Geometry.valid([panel, output({name: "DP-1",
            x: boxed.x, y: boxed.y, width: 2560, height: 1440})]));
        check("snap keeps raw when boxed in", Geometry.snap(100, 0, 2560, 1440, neighbour, {}).x === 100);

        // Moving a display to the nearest legal contact repairs typed overlaps.
        const repaired = Geometry.nearestContact([panel, Object.assign({}, external, {x: 1700})], "DP-1");
        check("repair overlap", repaired.x === 1920 && repaired.y === 0);
    }
}
