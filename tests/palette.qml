import QtQuick
import Quickshell
import Quickshell.Io

// Palette and shape rules for both modes, evaluated on the real Theme tokens.
ShellRoot {
    id: root
    property var failures: []
    property int cases: 0
    Theme { id: dark; darkMode: true; previewBlur: 0 }
    Theme { id: light; darkMode: false; previewBlur: 0 }

    function channel(value: real): real {
        return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    }
    function luminance(color: color): real {
        return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
    }
    function contrast(a: color, b: color): real {
        const x = luminance(a), y = luminance(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }
    function check(name: string, condition: bool): void {
        root.cases += 1;
        if (!condition) root.failures = [...root.failures, name];
    }
    function atLeast(name: string, value: real, minimum: real): void {
        check(name + " " + value.toFixed(2) + " < " + minimum, value >= minimum);
    }

    IpcHandler {
        target: "palette"
        function status(): string { return JSON.stringify({cases: root.cases, failures: root.failures}); }
    }

    Component.onCompleted: {
        for (const [mode, t] of [["dark", dark], ["light", light]]) {
            // Body text and every label tier read as text on each surface it sits on.
            for (const surface of ["panelSurface", "surfaceRaised", "inputSurface", "surfaceSelected"]) {
                atLeast(mode + " primary on " + surface, contrast(t.textPrimary, t[surface]), 7);
                atLeast(mode + " secondary on " + surface, contrast(t.textSecondary, t[surface]), 4.5);
                atLeast(mode + " muted on " + surface, contrast(t.textMuted, t[surface]), 4.5);
            }
            // Unavailable reasons stay legible where they are shown.
            atLeast(mode + " disabled on raised", contrast(t.textDisabled, t.surfaceRaised), 4);
            atLeast(mode + " disabled on hover", contrast(t.textDisabled, t.surfaceHover), 3.5);
            // Non-text boundaries users must find (WCAG 1.4.11 asks 3:1).
            atLeast(mode + " field outline", contrast(t.fieldOutline, t.inputSurface), 2.8);
            atLeast(mode + " focus ring on raised", contrast(t.focusInk, t.surfaceRaised), 3);
            atLeast(mode + " focus ring on selected", contrast(t.focusInk, t.surfaceSelected), 3);
            atLeast(mode + " accent on raised", contrast(t.accent, t.surfaceRaised), 3);
            atLeast(mode + " accent ink on accent", contrast(t.accentInk, t.accent), 4.5);
            // Tonal steps are visible but quiet.
            atLeast(mode + " raised vs panel", contrast(t.surfaceRaised, t.panelSurface), 1.08);
            atLeast(mode + " selected vs raised", contrast(t.surfaceSelected, t.surfaceRaised), 1.18);
            atLeast(mode + " selected vs hover", contrast(t.surfaceSelected, t.surfaceHover), 1.04);
            atLeast(mode + " slider track", contrast(t.sliderTrack, t.panelSurface), 1.3);
            check(mode + " meter is not selection", !Qt.colorEqual(t.meterFill, t.surfaceSelected));
            // A directory sits between the panel and the live cards above it.
            atLeast(mode + " directory above panel", contrast(t.surfaceDirectory, t.panelSurface), 1.03);
            atLeast(mode + " directory below raised", contrast(t.surfaceRaised, t.surfaceDirectory), 1.02);
            check(mode + " selection survives hover", !Qt.colorEqual(t.surfaceSelectedHover, t.surfaceHover));
            // Glass keeps enough tint that wallpaper detail never competes with text.
            check(mode + " frosted tint", t.frostedOpacity >= 0.88);

            // Corners stay small and nested shapes never exceed their container.
            check(mode + " small corners", t.radiusPanel <= 8);
            check(mode + " panel softer than cards", t.radiusPanel > t.radiusCard);
            check(mode + " cards contain controls", t.radiusCard >= t.radiusControl && t.radiusControl >= t.radiusSmall);
            check(mode + " focus ring fits", t.focusWidth >= 2 && t.focusWidth < t.compactControlHeight / 4);
        }
    }
}
