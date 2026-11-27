pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Scope {
    id: theme
    // Internal injection for isolated previews, not a user configuration API.
    property int previewBlur: -1
    SurfaceCapabilities { id: capabilities; enabled: theme.previewBlur < 0 }
    readonly property bool backdropBlur: previewBlur < 0 ? capabilities.blurAvailable : previewBlur === 1
    function refreshMaterial() { capabilities.refresh(); }
    required property bool darkMode
    // Complete validated snapshots may override colours without replacing QML.
    property var colors: ({})
    // Palette sync: the values below are mirrored in adapters/Hyprland.lua
    // (borders, groupbar). Keep both files in step when changing a colour;
    // accent is intentionally darker in Hyprland borders than in the shell.
    readonly property int panelPadding: 24
    readonly property int panelGap: 16
    // Shared spacing scale; one-off optical adjustments stay literal.
    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 16
    readonly property int compactControlHeight: 32
    readonly property int controlHeight: 36
    readonly property int fieldHeight: 40
    readonly property int maximumPanelHeight: 700
    // Stable width for tabs, search and details; height adapts to content.
    readonly property int maximumPanelWidth: 740
    readonly property int maximumTooltipWidth: 320
    readonly property int tooltipDelay: 500
    // Full header/footer band: a 32px control with 12px on each side.
    readonly property int stripHeight: 56
    // Shared motion rhythm: entrance settles gently; dismissal is shorter.
    readonly property int motionEnter: 200
    readonly property int motionExit: 140
    readonly property int motionPage: 160
    readonly property int motionResize: 200
    readonly property int motionDistance: 8
    readonly property int motionHintEnter: 100
    readonly property int motionHintExit: 80
    // Small, decorative corners: the panel reads one step softer than its
    // cards so nested shapes do not look interchangeable.
    readonly property int radiusPanel: 6
    readonly property int radiusInput: 4
    readonly property int radiusPopup: 6
    readonly property int radiusCard: 4
    readonly property int radiusControl: 4
    readonly property int radiusSmall: 3
    // Keyboard focus is drawn inside the control and never changes geometry.
    readonly property int focusWidth: 2
    // Neutral, layered surfaces: opacity is not a substitute for backdrop blur.
    readonly property color backdrop: colors.backdrop || (darkMode ? "#50000000" : "#18202730")
    readonly property color panelSurface: colors.panelSurface || (darkMode ? "#16191f" : "#f2f5f9")
    readonly property color backgroundSurface: colors.backgroundSurface || (darkMode ? "#111419" : "#e6ebf2")
    readonly property color surface: panelSurface
    readonly property color surfaceRaised: colors.surfaceRaised || (darkMode ? "#222730" : "#ffffff")
    readonly property color surfaceHover: colors.surfaceHover || (darkMode ? "#2d3440" : "#e3eaf3")
    readonly property color surfaceSelected: colors.surfaceSelected || (darkMode ? "#30415a" : "#d6e4f7")
    // A directory of links reads quieter than the live controls above it.
    readonly property color surfaceDirectory: colors.surfaceDirectory || Qt.tint(panelSurface, Qt.alpha(surfaceRaised, 0.55))
    // Filled controls (buttons, segmented tabs) sit clearly on both panel and card surfaces.
    readonly property color controlSurface: colors.controlSurface || (darkMode ? "#282e39" : "#eaeff6")
    // Selection survives hover: a slight lift instead of replacing the fill.
    readonly property color surfaceSelectedHover: Qt.tint(surfaceSelected, Qt.alpha(textPrimary, 0.06))
    readonly property color materialEdge: colors.materialEdge || (darkMode ? "#58424c5c" : "#281e293b")
    readonly property color materialShadow: colors.materialShadow || (darkMode ? "#78000000" : "#2c0f172a")
    // The compositor blurs only the matching surface region behind this tint.
    // Foreground cards stay slightly translucent over blur so layers breathe.
    readonly property real glassOpacity: backdropBlur ? (darkMode ? 0.86 : 0.90) : 1
    readonly property real cardOpacity: backdropBlur ? (darkMode ? 0.86 : 0.96) : 1
    readonly property real frostedOpacity: 0.90
    readonly property color cardSurface: Qt.alpha(surfaceRaised, cardOpacity)
    readonly property color directorySurface: Qt.alpha(surfaceDirectory, cardOpacity)
    readonly property color wallpaperScrim: colors.wallpaperScrim || (darkMode ? "#420b1118" : "#26e9ebef")
    readonly property color inputSurface: colors.inputSurface || (darkMode ? "#12151a" : "#ffffff")
    readonly property color textSelected: textPrimary
    readonly property color outline: colors.outline || (darkMode ? "#3e4754" : "#bcc7d6")
    // Decorative dividers; fieldOutline marks controls without heavy cages.
    readonly property color separator: colors.separator || (darkMode ? "#2b323d" : "#dfe6f0")
    readonly property color fieldOutline: colors.fieldOutline || (darkMode ? "#363f4d" : "#cbd5e2")
    readonly property color textPrimary: colors.textPrimary || (darkMode ? "#f1f3f5" : "#18202c")
    readonly property color textSecondary: colors.textSecondary || (darkMode ? "#c4cad3" : "#435062")
    readonly property color textMuted: colors.textMuted || (darkMode ? "#a5aebc" : "#556375")
    // Unavailable labels stay readable; only icons are dimmed further.
    readonly property color textDisabled: colors.textDisabled || (darkMode ? "#8891a0" : "#667487")
    readonly property color accent: colors.accent || (darkMode ? "#88aee8" : "#2b62b2")
    readonly property color focusInk: colors.focusInk || (darkMode ? "#a8c8f8" : "#2457a3")
    readonly property color sliderTrack: colors.sliderTrack || (darkMode ? "#3a4350" : "#cfd8e5")
    // Level fills (mixer streams) are not selection.
    readonly property color meterFill: colors.meterFill || (darkMode ? "#2a3545" : "#e3ecf7")
    readonly property color accentInk: colors.accentInk || (darkMode ? "#122036" : "#ffffff")
    readonly property color danger: colors.danger || (darkMode ? "#eb9c99" : "#a33a38")
    readonly property color accentWarm: colors.accentWarm || (darkMode ? "#e5bc82" : "#7d5112")

    // Typography scale; every text size in the shell maps to one of these.
    readonly property int fontSizeMicro: 10
    readonly property int fontSizeCaption: 11
    readonly property int fontSizeLabel: 12
    readonly property int fontSizeSmall: 13
    readonly property int fontSizeBody: 14
    readonly property int fontSizeControl: 14
    // Detail page titles; one step above card and notice titles.
    readonly property int fontSizeTitle: 16
    // The search field is the panel's primary input.
    readonly property int fontSizeSearch: 15
    readonly property int fontSizeHeading: 24
    readonly property string fontFamily: "Inter"
    readonly property real sectionLetterSpacing: 1.2
}
