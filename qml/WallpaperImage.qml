import QtQuick
import QtQuick.Window

Rectangle {
    id: root
    property bool asynchronous: true
    property bool nativeSize: false
    property bool cacheImage: false
    property url source
    property int fadeInDuration: 0
    property bool hasFrame: false
    property string fit: "cover"
    property color fallbackColor: "#191b1f"
    readonly property bool ready: picture.status === Image.Ready
    color: fallbackColor
    clip: true
    Image {
        id: picture
        anchors.fill: parent
        source: width > 0 && height > 0 ? root.source : ""
        asynchronous: root.asynchronous
        cache: root.cacheImage
        retainWhileLoading: true
        sourceSize.width: root.nativeSize ? -1 : Math.max(1, Math.ceil(width * Screen.devicePixelRatio))
        sourceSize.height: root.nativeSize ? -1 : Math.max(1, Math.ceil(height * Screen.devicePixelRatio))
        fillMode: root.fit === "contain" ? Image.PreserveAspectFit
            : root.fit === "stretch" ? Image.Stretch : Image.PreserveAspectCrop
        opacity: root.hasFrame ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.fadeInDuration } }
        onStatusChanged: {
            if (status === Image.Ready) root.hasFrame = true;
            else if (status === Image.Error || status === Image.Null) root.hasFrame = false;
        }
    }
}
