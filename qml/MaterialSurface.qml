import QtQuick
import QtQuick.Effects

// Flat tonal surface. Translucency is only used over a known, blurred wallpaper.
Rectangle {
    id: surface
    required property var materialTheme
    property bool frosted: false
    property bool shadowEnabled: false
    property real materialOpacity: frosted ? materialTheme.frostedOpacity : 1
    radius: materialTheme.radiusPanel
    color: Qt.alpha(materialTheme.panelSurface, materialOpacity)
    border.width: 1
    border.color: materialTheme.materialEdge
    RectangularShadow {
        visible: surface.shadowEnabled
        anchors.fill: parent
        z: -1
        radius: surface.radius
        blur: 20
        offset.y: 5
        color: surface.materialTheme.materialShadow
    }
}
