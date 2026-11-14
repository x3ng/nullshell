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
    readonly property int panelPadding: 22
    readonly property int panelGap: 14
    // Shared spacing scale; one-off optical adjustments stay literal.
    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 16
    readonly property int maximumPanelHeight: 700
    // Stable width for tabs, search and details; height adapts to content.
    readonly property int maximumPanelWidth: 740
    readonly property int maximumTooltipWidth: 320
    readonly property int tooltipDelay: 500
    readonly property int stripHeight: 48
    // Shared motion rhythm: entrance settles gently; dismissal is shorter.
    readonly property int motionEnter: 200
    readonly property int motionExit: 140
    readonly property int motionPage: 160
    readonly property int motionResize: 200
    readonly property int motionDistance: 8
    readonly property int motionHintEnter: 100
    readonly property int motionHintExit: 80
    readonly property int radiusPanel: 4
    readonly property int radiusInput: 3
    readonly property int radiusPopup: 4
    readonly property int radiusCard: 3
    readonly property int radiusControl: 3
    readonly property int radiusSmall: 3
    // Neutral, layered surfaces: opacity is not a substitute for backdrop blur.
    readonly property color backdrop: colors.backdrop || (darkMode ? "#50000000" : "#18202730")
    readonly property color panelSurface: colors.panelSurface || (darkMode ? "#202328" : "#f4f4f5")
    readonly property color backgroundSurface: colors.backgroundSurface || (darkMode ? "#1b1d21" : "#e9eaec")
    readonly property color surface: panelSurface
    readonly property color surfaceRaised: colors.surfaceRaised || (darkMode ? "#292d33" : "#fdfdfe")
    readonly property color surfaceHover: colors.surfaceHover || (darkMode ? "#34373d" : "#e6e8eb")
    readonly property color surfaceSelected: colors.surfaceSelected || (darkMode ? "#353e4b" : "#e0e7f0")
    readonly property color materialEdge: colors.materialEdge || (darkMode ? "#70535962" : "#30434a55")
    readonly property color materialShadow: colors.materialShadow || (darkMode ? "#40000000" : "#1a20242b")
    // The compositor blurs only the matching surface region behind this tint.
    readonly property real glassOpacity: backdropBlur ? (darkMode ? 0.78 : 0.72) : 1
    readonly property real frostedOpacity: darkMode ? 0.86 : 0.82
    readonly property color wallpaperScrim: colors.wallpaperScrim || (darkMode ? "#420b1118" : "#26e9ebef")
    readonly property color inputSurface: colors.inputSurface || (darkMode ? "#1b1f24" : "#ffffff")
    readonly property color textSelected: textPrimary
    readonly property color outline: colors.outline || (darkMode ? "#4a535c" : "#c4c8cf")
    readonly property color separator: colors.separator || (darkMode ? "#373e45" : "#dcdfe4")
    readonly property color textPrimary: colors.textPrimary || (darkMode ? "#f0f1f3" : "#24272d")
    readonly property color textSecondary: colors.textSecondary || (darkMode ? "#bdc1ca" : "#525965")
    readonly property color textMuted: colors.textMuted || (darkMode ? "#969da9" : "#69717e")
    readonly property color accent: colors.accent || (darkMode ? "#8aafe6" : "#3565a6")
    readonly property color accentInk: colors.accentInk || (darkMode ? "#15253e" : "#ffffff")
    readonly property color danger: colors.danger || (darkMode ? "#e99e9b" : "#a33d3b")
    readonly property color accentWarm: colors.accentWarm || (darkMode ? "#e4bb80" : "#805313")

    // Typography scale; every text size in the shell maps to one of these.
    readonly property int fontSizeMicro: 10
    readonly property int fontSizeCaption: 11
    readonly property int fontSizeSmall: 13
    readonly property int fontSizeBody: 14
    readonly property int fontSizeControl: 14
    readonly property int fontSizeHeading: 24
    readonly property string fontFamily: "Inter"
    readonly property real sectionLetterSpacing: 1.2
}
