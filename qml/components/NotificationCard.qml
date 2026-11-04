pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Notifications
import ".."
import "NotificationUtils.js" as NotificationUtils

MaterialSurface {
    id: card
    materialTheme: style
    required property Theme style
    required property var entry
    property var actions: []
    property string activationLabel: ""
    property bool compact: false
    materialEnabled: !compact
    property bool expandable: true
    property bool expanded: false
    property int maximumBodyHeight: 220
    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property bool hasMore: summaryText.truncated || bodyText.truncated || attachment.visible
    readonly property bool hovered: hover.hovered
    readonly property var buttons: Array.from(actions).filter(a => a.identifier !== "default")
    readonly property int pad: compact ? style.spaceSm : style.spaceMd
    signal activated()
    signal dismissRequested()
    signal actionRequested(var action)

    function activateCard() {
        if (activationLabel) activated();
        else if (expandable && (hasMore || expanded)) expanded = !expanded;
    }

    implicitHeight: content.implicitHeight + pad * 2
    radius: style.radiusCard
    color: compact ? (hovered ? style.surfaceHover : "transparent") : style.surfaceRaised
    border.width: compact && !activeFocus ? 0 : 1
    border.color: activeFocus ? style.accent : critical ? style.accentWarm : style.materialEdge
    activeFocusOnTab: visible
    Accessible.role: activationLabel ? Accessible.Button : Accessible.ListItem
    Accessible.name: [entry.appName, entry.summary].filter(Boolean).join(". ")
    Accessible.onPressAction: activateCard()
    Keys.onReturnPressed: activateCard()
    Keys.onEnterPressed: activateCard()
    Keys.onSpacePressed: activateCard()

    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        cursorShape: card.activationLabel || (card.expandable && (card.hasMore || card.expanded)) ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: card.activateCard()
    }

    ColumnLayout {
        id: content
        x: card.pad
        y: card.pad
        width: Math.max(1, card.width - card.pad * 2)
        spacing: card.style.spaceSm
        RowLayout {
            Layout.fillWidth: true
            spacing: card.style.spaceSm
            Rectangle {
                Layout.preferredWidth: card.compact ? 24 : 32
                Layout.preferredHeight: width
                radius: card.style.radiusControl
                color: card.style.surfaceHover
                IconImage {
                    id: appIcon
                    anchors.fill: parent
                    anchors.margins: 3
                    implicitSize: 26
                    source: NotificationUtils.imageSource(card.entry.appIcon || card.entry.image)
                    visible: source !== "" && status === Image.Ready
                }
                StatusIcon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    visible: !appIcon.visible
                    kind: "app"
                    ink: card.critical ? card.style.accentWarm : card.style.textMuted
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.entry.appName || "Application"
                textFormat: Text.PlainText
                color: card.critical ? card.style.accentWarm : card.style.textMuted
                elide: Text.ElideRight
                font.family: card.style.fontFamily
                font.pixelSize: card.style.fontSizeSmall
            }
            Text {
                text: NotificationUtils.timestamp(card.entry.time)
                color: card.style.textMuted
                font.family: card.style.fontFamily
                font.pixelSize: card.style.fontSizeCaption
            }
            ChoiceButton {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                style: card.style
                label: ""
                iconKind: "close"
                iconSize: 16
                Accessible.name: "Dismiss notification"
                onTriggered: card.dismissRequested()
            }
        }
        Text {
            id: summaryText
            Layout.fillWidth: true
            visible: text.length > 0
            text: card.entry.summary || ""
            textFormat: Text.PlainText
            color: card.style.textPrimary
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: card.expanded ? 2147483647 : card.compact ? 1 : 2
            elide: card.expanded ? Text.ElideNone : Text.ElideRight
            font.family: card.style.fontFamily
            font.pixelSize: card.compact ? card.style.fontSizeBody : card.style.fontSizeControl
            font.weight: Font.DemiBold
        }
        Flickable {
            id: bodyViewport
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(bodyText.implicitHeight, card.maximumBodyHeight)
            visible: bodyText.text.length > 0
            contentWidth: width
            contentHeight: bodyText.implicitHeight
            clip: true
            interactive: card.expanded && contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            Text {
                id: bodyText
                width: Math.max(1, bodyViewport.width)
                text: card.entry.body || ""
                // Match the server's plain-text capability instead of Qt's
                // HTML auto-detection, which can hide literal angle brackets.
                textFormat: Text.PlainText
                color: card.style.textSecondary
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: card.expanded ? 2147483647 : card.compact ? 2 : 3
                elide: card.expanded ? Text.ElideNone : Text.ElideRight
                font.family: card.style.fontFamily
                font.pixelSize: card.compact ? card.style.fontSizeSmall : card.style.fontSizeBody
            }
        }
        Image {
            id: attachment
            Layout.fillWidth: true
            Layout.preferredHeight: card.expanded ? 140 : 64
            visible: !card.compact && source !== "" && status === Image.Ready
            source: NotificationUtils.imageSource(card.entry.contentImage)
            sourceSize: Qt.size(800, 280)
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            asynchronous: true
        }
        Flow {
            id: actionFlow
            Layout.fillWidth: true
            visible: card.activationLabel !== "" || (!card.compact && card.buttons.length > 0)
            spacing: card.style.spaceSm
            ChoiceButton {
                width: Math.min(actionFlow.width, 150)
                height: 32
                visible: card.activationLabel !== ""
                style: card.style
                filled: true
                filledColor: card.style.surfaceHover
                label: card.activationLabel
                onTriggered: card.activated()
            }
            Repeater {
                model: card.compact ? [] : card.buttons
                ChoiceButton {
                    required property var modelData
                    width: Math.min(actionFlow.width, Math.max(96, Math.min(180, actionLabel.width + 24)))
                    height: 32
                    style: card.style
                    filled: true
                    filledColor: card.style.surfaceHover
                    textSize: card.style.fontSizeSmall
                    label: modelData.text || "Action"
                    Text {
                        id: actionLabel
                        visible: false
                        text: parent.label
                        textFormat: Text.PlainText
                        font.family: card.style.fontFamily
                        font.pixelSize: card.style.fontSizeSmall
                    }
                    onTriggered: card.actionRequested(modelData)
                }
            }
        }
        ChoiceButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            visible: card.expandable && (card.hasMore || card.expanded)
            style: card.style
            label: card.expanded ? "Show less" : "Show more"
            onTriggered: card.expanded = !card.expanded
        }
    }
}
