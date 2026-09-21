pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../themes"

// One note in the library grid, drawn in the note's own colour. Clicking opens
// the note; hovering reveals quick actions, and a right click (or the menu
// key) offers every action by name.
FocusScope {
    id: card

    property Theme theme: null
    property string noteTitle: ""
    property string snippet: ""
    property var tags: []
    property bool isPinned: false
    property bool isArchived: false
    property int priority: 0
    property string tint: "yellow"
    property bool onDesktop: false
    property bool current: false

    signal openRequested()
    // "pin", "unpin", "archive", "restore", "copy", "locate" or "delete".
    signal actionRequested(string action)

    readonly property bool hot: hover.hovered || card.activeFocus || actionsMenu.visible
    readonly property color background: theme ? theme.noteTint(tint, "bg") : "#fefce8"
    readonly property color edge: theme ? theme.noteTint(tint, "border") : "#fde047"
    readonly property color ink: theme ? theme.noteText : "#1c1917"
    readonly property color inkSoft: theme ? theme.noteTextSecondary : "#78716c"
    readonly property color priorityColor: {
        if (priority === 3) return theme ? theme.danger : "#ef4444"
        if (priority === 2) return theme ? theme.warning : "#f59e0b"
        return theme ? theme.textMuted : "#94a3b8"
    }
    readonly property string priorityLabel: {
        if (priority === 3) return qsTr("High")
        if (priority === 2) return qsTr("Medium")
        if (priority === 1) return qsTr("Low")
        return ""
    }

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: (noteTitle.trim().length ? noteTitle : qsTr("Untitled note"))
    Keys.onReturnPressed: card.openRequested()
    Keys.onEnterPressed: card.openRequested()
    Keys.onDeletePressed: card.actionRequested("delete")
    Keys.onMenuPressed: actionsMenu.popup(card, card.width / 2, card.height / 2)

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 14
        color: card.background
        border.width: card.current || card.activeFocus ? 2 : 1
        border.color: card.current || card.activeFocus
            ? (card.theme ? card.theme.accent : "#6366f1")
            : card.edge
        opacity: card.isArchived && !card.hot ? 0.7 : 1
        scale: tap.pressed ? 0.985 : 1

        Behavior on scale { NumberAnimation { duration: 90 } }
        Behavior on opacity { NumberAnimation { duration: card.theme ? card.theme.animShort : 120 } }

        // Priority reads as a single coloured edge, not another badge.
        Rectangle {
            visible: card.priority >= 2
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 10
            anchors.leftMargin: 0
            width: 3
            radius: 2
            color: card.priorityColor
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                AppIcon {
                    visible: card.isPinned
                    name: "pin"
                    size: 13
                    color: card.theme ? card.theme.accent : "#6366f1"
                    Layout.alignment: Qt.AlignVCenter
                }

                Label {
                    text: card.noteTitle.trim().length ? card.noteTitle : qsTr("Untitled note")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: card.noteTitle.trim().length ? card.ink : card.inkSoft
                    Layout.fillWidth: true
                    // Keep clear of the hover actions in the top-right corner.
                    Layout.rightMargin: card.hot ? quickActions.width - 6 : 0
                }
            }

            // Previews arrive as plain text from the core; rendering them as
            // plain text keeps any stray markup in a note body inert.
            Label {
                text: card.snippet.length ? card.snippet : qsTr("Empty note")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                font.pixelSize: 12
                font.italic: card.snippet.length === 0
                lineHeight: 1.3
                color: card.inkSoft
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: Text.AlignTop
                clip: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: card.tags.slice(0, 2)
                    delegate: Tag {
                        required property string modelData
                        theme: card.theme
                        text: "#" + modelData
                        textColor: card.ink
                        fillColor: Qt.rgba(card.edge.r, card.edge.g, card.edge.b, 0.35)
                        Layout.maximumWidth: 90
                    }
                }
                Tag {
                    theme: card.theme
                    visible: card.tags.length > 2
                    text: "+" + (card.tags.length - 2)
                    textColor: card.inkSoft
                    fillColor: Qt.rgba(card.edge.r, card.edge.g, card.edge.b, 0.25)
                }

                Item { Layout.fillWidth: true }

                Tag {
                    theme: card.theme
                    visible: card.priority > 0
                    text: card.priorityLabel
                    textColor: card.priorityColor
                    fillColor: Qt.rgba(card.edge.r, card.edge.g, card.edge.b, 0.3)
                }
                Tag {
                    theme: card.theme
                    visible: card.isArchived
                    text: qsTr("Archived")
                    textColor: card.inkSoft
                    fillColor: Qt.rgba(card.edge.r, card.edge.g, card.edge.b, 0.3)
                }
                AppIcon {
                    visible: card.onDesktop
                    name: "monitor"
                    size: 13
                    color: card.inkSoft
                    Layout.alignment: Qt.AlignVCenter
                    HoverHandler { id: desktopHint }
                    ToolTip.visible: desktopHint.hovered
                    ToolTip.text: qsTr("Open on the desktop")
                }
            }
        }

        // Quick actions, shown while the card is hovered or focused.
        Row {
            id: quickActions
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 8
            spacing: 2
            opacity: card.hot ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: card.theme ? card.theme.animShort : 120 } }

            component QuickAction: StyledButton {
                property string cardAction: ""
                property string hint: ""
                theme: card.theme
                variant: "ghost"
                iconSize: 14
                implicitWidth: 28
                implicitHeight: 28
                padding: 0
                focusPolicy: Qt.NoFocus
                iconColor: cardAction === "delete" && hovered
                    ? (card.theme ? card.theme.danger : "#ef4444") : card.ink
                ToolTip.visible: hovered
                ToolTip.text: hint
                ToolTip.delay: 400
                onClicked: if (cardAction.length) card.actionRequested(cardAction)
            }

            QuickAction {
                cardAction: card.isPinned ? "unpin" : "pin"
                iconName: card.isPinned ? "pin-off" : "pin"
                hint: card.isPinned ? qsTr("Unpin") : qsTr("Pin to the top of the list")
            }
            QuickAction {
                cardAction: card.isArchived ? "restore" : "archive"
                iconName: card.isArchived ? "archive-restore" : "archive"
                hint: card.isArchived ? qsTr("Restore from archive") : qsTr("Archive")
            }
            QuickAction { cardAction: "copy"; iconName: "copy"; hint: qsTr("Copy text") }
            QuickAction { cardAction: "delete"; iconName: "trash"; hint: qsTr("Delete") }
            QuickAction {
                id: moreButton
                iconName: "more"
                hint: qsTr("More actions")
                onClicked: actionsMenu.popup(moreButton, 0, moreButton.height)
            }
        }
    }

    HoverHandler { id: hover }

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: {
            card.forceActiveFocus()
            card.openRequested()
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: function(eventPoint) {
            card.forceActiveFocus()
            actionsMenu.popup(card, eventPoint.position.x, eventPoint.position.y)
        }
    }

    Menu {
        id: actionsMenu
        MenuItem { text: qsTr("Open"); onTriggered: card.openRequested() }
        MenuItem {
            text: qsTr("Bring here")
            onTriggered: card.actionRequested("locate")
        }
        MenuSeparator {}
        MenuItem {
            text: card.isPinned ? qsTr("Unpin") : qsTr("Pin to top")
            onTriggered: card.actionRequested(card.isPinned ? "unpin" : "pin")
        }
        MenuItem {
            text: card.isArchived ? qsTr("Restore from archive") : qsTr("Archive")
            onTriggered: card.actionRequested(card.isArchived ? "restore" : "archive")
        }
        MenuItem { text: qsTr("Copy text"); onTriggered: card.actionRequested("copy") }
        MenuSeparator {}
        MenuItem { text: qsTr("Delete…"); onTriggered: card.actionRequested("delete") }
    }
}
