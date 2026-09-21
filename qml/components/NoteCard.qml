pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../themes"
import "Reminders.js" as Reminders

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
    // "<unix seconds>|<recurrence>", or "" when the note has no reminder.
    property string reminder: ""
    // A note in the trash, deleted at deletedAt (Unix ms); it can only be
    // restored or deleted for good.
    property bool trashed: false
    property real deletedAt: 0
    // Multi-selection: this card is selected, and whether any card is (then
    // a plain click selects instead of opening).
    property bool selected: false
    property bool selecting: false
    // The content is locked with the master password.
    property bool locked: false

    // A click with Ctrl (toggle) or Shift (range), or any click while cards
    // are selected.
    signal selectRequested(bool range)

    readonly property string trashLabel: {
        if (!trashed) return ""
        const days = Math.floor((Date.now() - deletedAt) / 86400000)
        const left = Math.max(0, 30 - days)
        const ago = days === 0 ? qsTr("Deleted today") : qsTr("Deleted %n day(s) ago", "", days)
        return ago + " · " + qsTr("gone for good in %n day(s)", "", left)
    }

    signal openRequested()
    // "pin", "unpin", "archive", "restore", "copy", "locate", "reminder",
    // "delete" (to the trash), "restore-trash", "delete-forever", "lock" or
    // "unlock-note".
    signal actionRequested(string action)

    readonly property bool hot: hover.hovered || card.activeFocus || actionsMenu.visible || trashMenu.visible
    readonly property color background: theme ? theme.noteTint(tint, "bg") : "#fefce8"
    readonly property color edge: theme ? theme.noteTint(tint, "border") : "#fde047"
    readonly property color ink: theme ? theme.noteText : "#1c1917"
    readonly property color inkSoft: theme ? theme.noteTextSecondary : "#78716c"
    readonly property string highlight: theme && theme.isDark ? "#806a1f" : "#fde68a"
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
    Keys.onReturnPressed: if (!card.trashed) card.openRequested()
    Keys.onEnterPressed: if (!card.trashed) card.openRequested()
    Keys.onDeletePressed: card.actionRequested(card.trashed ? "delete-forever" : "delete")
    Keys.onSpacePressed: card.selectRequested(false)
    Keys.onMenuPressed: (card.trashed ? trashMenu : actionsMenu).popup(card, card.width / 2, card.height / 2)

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 14
        color: card.background
        border.width: card.selected || card.current || card.activeFocus ? 2 : 1
        border.color: card.selected || card.current || card.activeFocus
            ? (card.theme ? card.theme.accent : "#6366f1")
            : card.edge
        opacity: (card.isArchived || card.trashed) && !card.hot && !card.selected ? 0.7 : 1

        // Selection mark.
        Rectangle {
            objectName: "selectionMark"
            visible: card.selected || (card.selecting && card.hot)
            z: 2
            x: 10
            y: 12
            width: 20
            height: 20
            radius: 10
            color: card.selected ? (card.theme ? card.theme.accent : "#6366f1") : (card.theme ? card.theme.surface : "white")
            border.width: 2
            border.color: card.theme ? card.theme.accent : "#6366f1"
            AppIcon {
                anchors.centerIn: parent
                visible: card.selected
                name: "check"
                size: 12
                strokeWidth: 3
                color: "white"
            }
        }
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
                // Room for the selection mark.
                Layout.leftMargin: card.selected || card.selecting ? 22 : 0
                spacing: 6

                AppIcon {
                    visible: card.locked
                    name: "lock"
                    size: 13
                    color: card.inkSoft
                    Layout.alignment: Qt.AlignVCenter
                }
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
                // Search results mark each match with U+E000/U+E001. The note
                // text is escaped first, so only the highlight is markup.
                readonly property bool marked: card.snippet.indexOf("\ue000") >= 0
                text: {
                    if (card.locked) return qsTr("Locked note")
                    if (!card.snippet.length) return qsTr("Empty note")
                    if (!marked) return card.snippet
                    const escaped = card.snippet.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                    const mark = "<span style=\"background-color:" + card.highlight + "; font-weight:600;\">"
                    let html = escaped.replace(/\ue000/g, mark).replace(/\ue001/g, "</span>")
                    // A preview cut short can end inside a match.
                    if ((html.match(/<span/g) || []).length > (html.match(/<\/span>/g) || []).length) html += "</span>"
                    return html
                }
                textFormat: marked ? Text.RichText : Text.PlainText
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                font.pixelSize: 12
                font.italic: card.snippet.length === 0 || card.locked
                lineHeight: 1.3
                color: card.inkSoft
                Layout.fillWidth: true
                Layout.fillHeight: true
                verticalAlignment: Text.AlignTop
                clip: true
            }

            // The reminder, if any; clicking it edits the reminder.
            Rectangle {
                id: reminderChip
                objectName: "reminderChip"
                visible: card.reminder.length > 0
                Layout.maximumWidth: parent.width
                implicitWidth: reminderRow.implicitWidth + 14
                implicitHeight: 22
                radius: height / 2
                color: reminderTap.hovered
                    ? Qt.rgba(card.edge.r, card.edge.g, card.edge.b, 0.55)
                    : Qt.rgba(card.edge.r, card.edge.g, card.edge.b, 0.35)
                RowLayout {
                    id: reminderRow
                    anchors.fill: parent
                    anchors.leftMargin: 7
                    anchors.rightMargin: 7
                    spacing: 5
                    AppIcon {
                        name: "bell"
                        size: 12
                        color: card.ink
                    }
                    Label {
                        text: Reminders.describe(card.reminder)
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: card.ink
                        Layout.fillWidth: true
                    }
                }
                HoverHandler { id: reminderTap; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: card.actionRequested("reminder")
                }
                ToolTip.visible: reminderTap.hovered
                ToolTip.text: qsTr("Edit reminder")
                ToolTip.delay: 400
            }

            Label {
                visible: card.trashed
                text: card.trashLabel
                font.pixelSize: 11
                color: card.inkSoft
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                visible: !card.trashed
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
                visible: card.trashed
                cardAction: "restore-trash"
                iconName: "archive-restore"
                hint: qsTr("Restore")
            }
            QuickAction {
                visible: card.trashed
                cardAction: "delete-forever"
                iconName: "trash"
                hint: qsTr("Delete for good")
            }
            QuickAction {
                visible: !card.trashed
                cardAction: card.isPinned ? "unpin" : "pin"
                iconName: card.isPinned ? "pin-off" : "pin"
                hint: card.isPinned ? qsTr("Unpin") : qsTr("Pin to the top of the list")
            }
            QuickAction {
                visible: !card.trashed
                cardAction: card.isArchived ? "restore" : "archive"
                iconName: card.isArchived ? "archive-restore" : "archive"
                hint: card.isArchived ? qsTr("Restore from archive") : qsTr("Archive")
            }
            QuickAction { visible: !card.trashed; cardAction: "copy"; iconName: "copy"; hint: qsTr("Copy text") }
            QuickAction {
                visible: !card.trashed
                cardAction: "reminder"
                iconName: "bell"
                hint: card.reminder.length > 0 ? qsTr("Edit reminder") : qsTr("Add reminder")
            }
            QuickAction { visible: !card.trashed; cardAction: "delete"; iconName: "trash"; hint: qsTr("Move to trash") }
            QuickAction {
                id: moreButton
                iconName: "more"
                hint: qsTr("More actions")
                onClicked: (card.trashed ? trashMenu : actionsMenu).popup(moreButton, 0, moreButton.height)
            }
        }
    }

    HoverHandler { id: hover }

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: {
            card.forceActiveFocus()
            const modifiers = tap.point.modifiers
            if (modifiers & Qt.ShiftModifier) card.selectRequested(true)
            else if ((modifiers & Qt.ControlModifier) || card.selecting || card.trashed) card.selectRequested(false)
            else card.openRequested()
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: function(eventPoint) {
            card.forceActiveFocus()
            (card.trashed ? trashMenu : actionsMenu).popup(card, eventPoint.position.x, eventPoint.position.y)
        }
    }

    Menu {
        id: trashMenu
        MenuItem { text: qsTr("Restore"); onTriggered: card.actionRequested("restore-trash") }
        MenuItem { text: qsTr("Delete for Good…"); onTriggered: card.actionRequested("delete-forever") }
        MenuSeparator {}
        MenuItem { text: card.selected ? qsTr("Deselect") : qsTr("Select"); onTriggered: card.selectRequested(false) }
    }

    Menu {
        id: actionsMenu
        MenuItem { text: qsTr("Open"); onTriggered: card.openRequested() }
        MenuItem { text: card.selected ? qsTr("Deselect") : qsTr("Select"); onTriggered: card.selectRequested(false) }
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
        MenuItem { text: qsTr("Copy text"); enabled: !card.locked; onTriggered: card.actionRequested("copy") }
        MenuItem {
            text: card.locked ? qsTr("Remove Lock…") : qsTr("Lock with Password…")
            onTriggered: card.actionRequested(card.locked ? "unlock-note" : "lock")
        }
        MenuItem {
            text: card.reminder.length > 0 ? qsTr("Edit reminder…") : qsTr("Add reminder…")
            onTriggered: card.actionRequested("reminder")
        }
        MenuSeparator {}
        MenuItem { text: qsTr("Move to Trash"); onTriggered: card.actionRequested("delete") }
    }
}
