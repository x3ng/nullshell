import QtQuick
import QtQuick.Effects

// Shared finish. Translucency is only used over a known, blurred wallpaper.
Rectangle {
    id: surface
    required property var materialTheme
    property bool materialEnabled: true
    property bool frosted: false
    property bool shadowEnabled: false
    property real materialOpacity: frosted ? materialTheme.frostedOpacity : 1
    radius: materialTheme.radiusPanel
    color: materialTheme.panelSurface
    border.width: 1
    border.color: materialTheme.materialEdge
    gradient: materialEnabled ? finish : null
    Gradient {
        id: finish
        GradientStop { position: 0; color: Qt.alpha(surface.materialTheme.materialTop, surface.materialOpacity) }
        GradientStop { position: 1; color: Qt.alpha(surface.materialTheme.materialBottom, surface.materialOpacity) }
    }
    RectangularShadow {
        visible: surface.shadowEnabled && surface.materialEnabled
        anchors.fill: parent
        z: -1
        radius: surface.radius
        blur: 24
        offset.y: 6
        color: surface.materialTheme.materialShadow
    }
    Rectangle {
        visible: surface.materialEnabled
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, surface.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: surface.materialTheme.materialHighlight
    }
}
