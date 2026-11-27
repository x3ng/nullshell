.pragma library

// Placement rules for independent outputs: no positive-area overlap, and every
// display reachable from the others through a shared edge of positive length.
// Coordinates are Hyprland layout pixels; disabled and mirrored outputs do not
// occupy layout space.

function logicalSize(output) {
    const scale = Math.max(0.25, Number(output.scale) || 1);
    const rotated = Number(output.transform) % 2 === 1;
    return {
        width: Math.round((rotated ? output.height : output.width) / scale),
        height: Math.round((rotated ? output.width : output.height) / scale)
    };
}

function placed(output) {
    return !!output && output.enabled && !output.mirror_of && output.width > 0 && output.height > 0;
}

function rect(output, x, y) {
    const size = logicalSize(output);
    const left = x ?? Math.round(output.x);
    const top = y ?? Math.round(output.y);
    return {name: output.name, key: output.key, x0: left, y0: top,
        x1: left + size.width, y1: top + size.height, width: size.width, height: size.height};
}

function rects(outputs) {
    return (outputs || []).filter(placed).map(output => rect(output));
}

function spanX(a, b) { return Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0); }
function spanY(a, b) { return Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0); }
function overlaps(a, b) { return spanX(a, b) > 0 && spanY(a, b) > 0; }
function touches(a, b) {
    const ix = spanX(a, b), iy = spanY(a, b);
    return (ix === 0 && iy > 0) || (iy === 0 && ix > 0);
}

function list(names) {
    return names.length < 3 ? names.join(" and ")
        : names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
}

function issues(outputs) {
    const items = rects(outputs);
    const result = [];
    for (let i = 0; i < items.length; i++)
        for (let j = i + 1; j < items.length; j++)
            if (overlaps(items[i], items[j]))
                result.push({kind: "overlap", names: [items[j].name, items[i].name],
                    text: items[j].name + " overlaps " + items[i].name + "."});

    // Overlapping pairs are reported above, so they count as joined here.
    const group = items.map((_, index) => index);
    const find = index => group[index] === index ? index : (group[index] = find(group[index]));
    for (let i = 0; i < items.length; i++)
        for (let j = i + 1; j < items.length; j++)
            if (touches(items[i], items[j]) || overlaps(items[i], items[j])) group[find(j)] = find(i);
    const sizes = {};
    items.forEach((_, index) => sizes[find(index)] = (sizes[find(index)] || 0) + 1);
    let main = -1;
    items.forEach((_, index) => {
        const root = find(index);
        if (main < 0 || sizes[root] > sizes[main]) main = root;
    });
    const loose = items.filter((_, index) => find(index) !== main).map(item => item.name);
    if (loose.length)
        result.push({kind: "detached", names: loose,
            text: list(loose) + (loose.length === 1 ? " does" : " do") + " not touch the other displays."});
    return result;
}

function valid(outputs) {
    return rects(outputs).length > 0 && issues(outputs).length === 0;
}

function free(candidate, others) {
    return !others.some(other => overlaps(candidate, other));
}

// Positions where a width×height display shares an edge with one neighbour.
// Each contact keeps the requested position along the shared edge, limited to
// a positive-length contact, and then considers flush edge alignment.
function contacts(rawX, rawY, width, height, other) {
    const clampY = y => Math.max(other.y0 - height + 1, Math.min(other.y1 - 1, y));
    const clampX = x => Math.max(other.x0 - width + 1, Math.min(other.x1 - 1, x));
    return [
        {x: other.x1, y: clampY(rawY), axis: "x", guide: other.x1},
        {x: other.x0 - width, y: clampY(rawY), axis: "x", guide: other.x0},
        {x: clampX(rawX), y: other.y1, axis: "y", guide: other.y1},
        {x: clampX(rawX), y: other.y0 - height, axis: "y", guide: other.y0}
    ];
}

function align(value, length, lines, limit) {
    let best = {value: value, guide: null, distance: limit};
    for (const line of lines)
        for (const target of [line, line - length]) {
            const distance = Math.abs(target - value);
            if (distance <= best.distance) best = {value: target, guide: line, distance: distance};
        }
    return best;
}

// Snaps a dragged display at (rawX, rawY). Thresholds are layout pixels; a held
// result keeps its edge until the pointer leaves the wider release band.
function snap(rawX, rawY, width, height, others, options) {
    const opts = options || {};
    const enter = opts.enter ?? 32;
    const exit = Math.max(enter, opts.exit ?? enter * 2);
    const held = opts.held || null;
    const x = Math.round(rawX), y = Math.round(rawY);
    let best = null;
    for (const other of others) {
        for (const candidate of contacts(x, y, width, height, other)) {
            const primary = candidate.axis === "x" ? Math.abs(candidate.x - x) : Math.abs(candidate.y - y);
            const secondary = candidate.axis === "x" ? Math.abs(candidate.y - y) : Math.abs(candidate.x - x);
            const sticky = held && held.axis === candidate.axis
                && (candidate.axis === "x" ? held.x === candidate.x : held.y === candidate.y);
            const limit = sticky ? exit : enter;
            if (primary > limit || secondary > limit) continue;

            // Align the free axis to any display edge, preserving contact.
            const lines = [];
            for (const item of others)
                lines.push(candidate.axis === "x" ? item.y0 : item.x0,
                    candidate.axis === "x" ? item.y1 : item.x1);
            const alignHeld = held && (candidate.axis === "x" ? held.guideY : held.guideX);
            const along = align(candidate.axis === "x" ? candidate.y : candidate.x,
                candidate.axis === "x" ? height : width, lines,
                alignHeld !== null && alignHeld !== undefined ? exit : enter);
            const result = candidate.axis === "x"
                ? {x: candidate.x, y: along.value, axis: "x", guideX: candidate.guide, guideY: along.guide}
                : {x: along.value, y: candidate.y, axis: "y", guideX: along.guide, guideY: candidate.guide};
            const box = {x0: result.x, y0: result.y, x1: result.x + width, y1: result.y + height};
            if (!others.some(o => touches(box, o)) || !free(box, others)) {
                // Alignment may slide the display off its neighbour; fall back to contact only.
                const plain = {x0: candidate.x, y0: candidate.y, x1: candidate.x + width, y1: candidate.y + height};
                if (!free(plain, others)) continue;
                Object.assign(result, {x: candidate.x, y: candidate.y},
                    candidate.axis === "x" ? {guideY: null} : {guideX: null});
            }
            const distance = Math.hypot(result.x - x, result.y - y) - (sticky ? exit : 0);
            if (!best || distance < best.distance) best = Object.assign(result, {distance: distance});
        }
    }
    if (!best) return {x: x, y: y, axis: "", guideX: null, guideY: null, snapped: false};
    delete best.distance;
    best.snapped = true;
    return best;
}

// The nearest flush position for one display against all others.
function nearestContact(outputs, name) {
    const target = (outputs || []).find(output => output.name === name);
    if (!placed(target)) return null;
    const self = rect(target);
    const others = rects(outputs).filter(item => item.name !== name);
    if (!others.length) return {x: self.x0, y: self.y0};
    return snap(self.x0, self.y0, self.width, self.height, others,
        {enter: Number.MAX_SAFE_INTEGER, exit: Number.MAX_SAFE_INTEGER});
}

// Reattaches every display outside the largest connected group, and resolves
// overlaps by moving the later display. Returns {name: {x, y}} for changed outputs.
function arrange(outputs) {
    const working = (outputs || []).map(output => Object.assign({}, output));
    const moved = {};
    for (let pass = 0; pass < working.length * 2; pass++) {
        const problem = issues(working)[0];
        if (!problem) break;
        const name = problem.names[0];
        const index = working.findIndex(output => output.name === name);
        const others = working.filter(output => output.name !== name);
        const settled = others.filter(output => !issues(others).some(issue => issue.names.includes(output.name)));
        const position = nearestContact(settled.concat([working[index]]), name);
        if (!position) break;
        if (position.x === working[index].x && position.y === working[index].y) break;
        working[index].x = position.x;
        working[index].y = position.y;
        moved[name] = {x: position.x, y: position.y};
    }
    return moved;
}
