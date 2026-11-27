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
    readonly property int panelPadding: 18
    readonly property int panelGap: 12
    // Shared spacing scale; one-off optical adjustments stay literal.
    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 16
    readonly property int compactControlHeight: 32
    readonly property int controlHeight: 36
    readonly property int fieldHeight: 42
    readonly property int maximumPanelHeight: 700
    // Compact width keeps status tiles, sliders and footer dense without dead space.
    readonly property int maximumPanelWidth: 620
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
    // Neutral, layered surfaces: base, cards and hover stay strictly achromatic
    // (zero violet/slate cast in light mode) so active cerulean tints read crisp.
    readonly property color backdrop: colors.backdrop || (darkMode ? "#50000000" : "#18181b24")
    readonly property color panelSurface: colors.panelSurface || (darkMode ? "#16181b" : "#f3f4f5")
    readonly property color backgroundSurface: colors.backgroundSurface || (darkMode ? "#111215" : "#e7e8ea")
    readonly property color surface: panelSurface
    readonly property color surfaceRaised: colors.surfaceRaised || (darkMode ? "#202227" : "#ffffff")
    readonly property color surfaceHover: colors.surfaceHover || (darkMode ? "#2c2f35" : "#e2e4e7")
    // Active / selected state uses pure ~204° cerulean blue (no lavender/purple cast).
    readonly property color surfaceSelected: colors.surfaceSelected || (darkMode ? "#1b3d5c" : "#b8def8")
    // A directory of links reads quieter than the live controls above it.
    readonly property color surfaceDirectory: colors.surfaceDirectory || Qt.tint(panelSurface, Qt.alpha(surfaceRaised, 0.55))
    // Filled controls (buttons, segmented tabs) sit clearly on both panel and card surfaces.
    readonly property color controlSurface: colors.controlSurface || (darkMode ? "#272a30" : "#eceef0")
    // Selection survives hover: lift chroma/depth instead of washing out to grey.
    readonly property color surfaceSelectedHover: colors.surfaceSelectedHover || (darkMode ? "#224b70" : "#a4d3f5")
    readonly property color materialEdge: colors.materialEdge || (darkMode ? "#58424750" : "#26181a1f")
    readonly property color materialShadow: colors.materialShadow || (darkMode ? "#78000000" : "#280f141c")
    // The compositor blurs only the matching surface region behind this tint.
    // Foreground cards stay slightly translucent over blur so layers breathe.
    readonly property real glassOpacity: backdropBlur ? (darkMode ? 0.86 : 0.92) : 1
    readonly property real cardOpacity: backdropBlur ? (darkMode ? 0.86 : 0.97) : 1
    readonly property real frostedOpacity: 0.90
    readonly property color cardSurface: Qt.alpha(surfaceRaised, cardOpacity)
    readonly property color directorySurface: Qt.alpha(surfaceDirectory, cardOpacity)
    readonly property color wallpaperScrim: colors.wallpaperScrim || (darkMode ? "#420b1118" : "#26e9ebed")
    readonly property color inputSurface: colors.inputSurface || (darkMode ? "#121316" : "#ffffff")
    readonly property color textSelected: textPrimary
    readonly property color outline: colors.outline || (darkMode ? "#3e424b" : "#b8bcc4")
    // Decorative dividers; fieldOutline marks controls without heavy cages.
    readonly property color separator: colors.separator || (darkMode ? "#2a2d34" : "#e2e4e7")
    readonly property color fieldOutline: colors.fieldOutline || (darkMode ? "#363a42" : "#cccfd5")
    readonly property color textPrimary: colors.textPrimary || (darkMode ? "#f2f4f6" : "#17191c")
    readonly property color textSecondary: colors.textSecondary || (darkMode ? "#c7ccd2" : "#3b4048")
    readonly property color textMuted: colors.textMuted || (darkMode ? "#a5acb6" : "#4b525c")
    // Unavailable labels stay readable; only icons are dimmed further.
    readonly property color textDisabled: colors.textDisabled || (darkMode ? "#8a919b" : "#656d78")
    readonly property color accent: colors.accent || (darkMode ? "#6bb8f5" : "#0b63b6")
    readonly property color focusInk: colors.focusInk || (darkMode ? "#9bd0fa" : "#08549c")
    readonly property color sliderTrack: colors.sliderTrack || (darkMode ? "#383c44" : "#cdd1d7")
    // Continuous level fills stand out clearly against white/dark tracks.
    readonly property color sliderFill: colors.sliderFill || (darkMode ? "#234c72" : "#a9d6f5")
    readonly property color sliderMutedFill: colors.sliderMutedFill || (darkMode ? "#2a2d33" : "#dcdfe4")
    readonly property color keycapSurface: colors.keycapSurface || Qt.alpha(textPrimary, darkMode ? 0.09 : 0.07)
    // Level fills (mixer streams) are not selection.
    readonly property color meterFill: colors.meterFill || (darkMode ? "#1f354a" : "#cbe7fa")
    readonly property color accentInk: colors.accentInk || (darkMode ? "#0b1d30" : "#ffffff")
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
