pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Scope {
    required property bool darkMode
    // Palette sync: the values below are mirrored in hypr/appearance.lua
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
    readonly property int maximumPanelWidth: 600
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
    readonly property int radiusPanel: 24
    readonly property int radiusInput: 14
    readonly property int radiusPopup: 12
    readonly property int radiusCard: 16
    readonly property int radiusControl: 10
    readonly property int radiusSmall: 3
    // Neutral, layered surfaces: opacity is not a substitute for backdrop blur.
    readonly property color backdrop: darkMode ? "#50000000" : "#18202730"
    readonly property color panelSurface: darkMode ? "#202328" : "#f4f4f2"
    readonly property color surface: panelSurface
    readonly property color surfaceRaised: darkMode ? "#292d33" : "#fdfdfc"
    readonly property color surfaceHover: darkMode ? "#343a41" : "#e7eae8"
    readonly property color surfaceSelected: darkMode ? "#3a4545" : "#dce6e1"
    readonly property color materialTop: darkMode ? "#2b3036" : "#fdfdfc"
    readonly property color materialBottom: darkMode ? "#22262b" : "#f0f2ef"
    readonly property color materialEdge: darkMode ? "#850d1116" : "#302c3b34"
    readonly property color materialHighlight: darkMode ? "#12ffffff" : "#c0ffffff"
    readonly property color materialShadow: darkMode ? "#60000000" : "#24202b25"
    readonly property real frostedOpacity: darkMode ? 0.9 : 0.94
    readonly property color wallpaperScrim: darkMode ? "#420b1118" : "#26e8eeeb"
    readonly property color inputSurface: darkMode ? "#1b1f24" : "#ffffff"
    readonly property color textSelected: textPrimary
    readonly property color outline: darkMode ? "#4a535c" : "#c1cbc5"
    readonly property color separator: darkMode ? "#373e45" : "#dce1dc"
    readonly property color textPrimary: darkMode ? "#f0f1f3" : "#24272d"
    readonly property color textSecondary: darkMode ? "#bdc1ca" : "#525965"
    readonly property color textMuted: darkMode ? "#969da9" : "#69717e"
    readonly property color accent: darkMode ? "#79ad9d" : "#1c7057"
    readonly property color accentInk: darkMode ? "#132a23" : "#ffffff"
    readonly property color danger: darkMode ? "#e99e9b" : "#a33d3b"
    readonly property color accentWarm: darkMode ? "#e4bb80" : "#805313"

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
