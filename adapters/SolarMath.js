.pragma library

// Local NOAA solar-coordinate calculation (UTC Unix seconds throughout,
// standard sunrise altitude -0.833 degrees). Pure arithmetic; no child process.

function remEuclid(x, m) {
    var r = x % m;
    return r < 0 ? r + m : r;
}

function sinDeg(v) {
    return Math.sin(v * Math.PI / 180.0);
}

function cosDeg(v) {
    return Math.cos(v * Math.PI / 180.0);
}

function daylight(time, lat, lon) {
    var t = (time / 86400.0 + 2440587.5 - 2451545.0) / 36525.0;
    var l = remEuclid(280.46646 + t * (36000.76983 + 0.0003032 * t), 360.0);
    var m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
    var e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    var c = sinDeg(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
        + sinDeg(2.0 * m) * (0.019993 - 0.000101 * t)
        + sinDeg(3.0 * m) * 0.000289;
    var omega = 125.04 - 1934.136 * t;
    var lambda = l + c - 0.00569 - 0.00478 * sinDeg(omega);
    var epsilon = 23.0
        + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - 0.001813 * t))) / 60.0) / 60.0
        + 0.00256 * cosDeg(omega);
    var decl = Math.asin(sinDeg(epsilon) * sinDeg(lambda));
    var y = Math.pow(Math.tan(epsilon * Math.PI / 360.0), 2);
    var eq = 4.0 * (
        y * sinDeg(2.0 * l)
        - 2.0 * e * sinDeg(m)
        + 4.0 * e * y * sinDeg(m) * cosDeg(2.0 * l)
        - 0.5 * y * y * sinDeg(4.0 * l)
        - 1.25 * e * e * sinDeg(2.0 * m)
    ) * 180.0 / Math.PI;
    var hour = remEuclid(remEuclid(time, 86400.0) / 60.0 + eq + 4.0 * lon, 1440.0) / 4.0 - 180.0;
    return sinDeg(lat) * Math.sin(decl) + cosDeg(lat) * Math.cos(decl) * cosDeg(hour) >= sinDeg(-0.833);
}

function calculate(lat, lon, timestamp) {
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || !Number.isFinite(timestamp)
            || lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0
            || timestamp < 946684800.0 || timestamp >= 4102444800.0) {
        return null;
    }
    var light = daylight(timestamp, lat, lon);
    var previous = timestamp;
    // Minute-resolution scan across two days, refined to 1-second precision.
    for (var minute = 1; minute <= 2880; minute++) {
        var end = timestamp + minute * 60.0;
        if (daylight(end, lat, lon) !== light) {
            while (end - previous > 1.0) {
                var mid = (previous + end) / 2.0;
                if (daylight(mid, lat, lon) === light) previous = mid;
                else end = mid;
            }
            return {version: 1, dark: !light, next_transition: end};
        }
        previous = end;
    }
    return {version: 1, dark: !light, next_transition: null};
}
