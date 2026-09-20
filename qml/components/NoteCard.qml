pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../themes"

ItemDelegate {
    id: card

    property Theme theme: null
    property string noteTitle: ""
    property string snippet: ""
    property var tags: []
    property bool isPinned: false
    property bool isArchived: false
    property int priority: 0
    signal bringHereRequested()

    readonly property color accentColor: {
        if (priority === 3) return theme ? theme.danger : "#ef4444"
        if (priority === 2) return theme ? theme.warning : "#f59e0b"
        if (isPinned) return theme ? theme.accent : "#6366f1"
        return theme ? theme.border : "#e2e8f0"
    }
    readonly property string priorityLabel: {
        if (priority === 3) return qsTr("High")
        if (priority === 2) return qsTr("Medium")
        if (priority === 1) return qsTr("Low")
        return ""
    }

    implicitWidth: ListView.view ? ListView.view.width : 320
    implicitHeight: layout.implicitHeight + 22
    padding: 0
    hoverEnabled: true

    background: Rectangle {
        radius: card.theme ? card.theme.radiusLg : 12
        color: {
            if (card.down) return card.theme ? card.theme.surfaceActive : "#e2e8f0"
            if (card.hovered || card.highlighted) return card.theme ? card.theme.surfaceHover : "#f1f5f9"
            return card.theme ? card.theme.surface : "#ffffff"
        }
        border.width: 1
        border.color: card.activeFocus || card.highlighted
            ? (card.theme ? card.theme.accent : "#6366f1")
            : (card.theme ? card.theme.border : "#e2e8f0")
        opacity: card.isArchived && !card.hovered ? 0.72 : 1.0

        // The rail is the only colour the row carries, so priority and pinning
        // read at a glance without competing with the note text.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: 3
            radius: width
            color: card.accentColor
            visible: card.priority > 0 || card.isPinned
        }

        Behavior on color {
            ColorAnimation { duration: card.theme ? card.theme.animShort : 120 }
        }
    }

    contentItem: RowLayout {
        id: layout
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    text: card.noteTitle.trim().length ? card.noteTitle : qsTr("Untitled note")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: card.theme ? card.theme.textPrimary : "#0f172a"
                    Layout.fillWidth: true
                }

                Tag {
                    theme: card.theme
                    text: card.priorityLabel
                    visible: card.priority > 0
                    textColor: card.accentColor
                    fillColor: {
                        if (card.priority === 3) return card.theme ? card.theme.dangerSubtle : "#fee2e2"
                        if (card.priority === 2) return card.theme ? card.theme.warningSubtle : "#fef3c7"
                        return card.theme ? card.theme.surfaceHover : "#f1f5f9"
                    }
                }

                Tag {
                    theme: card.theme
                    text: qsTr("Pinned")
                    visible: card.isPinned
                    textColor: card.theme ? card.theme.accent : "#6366f1"
                    fillColor: card.theme ? card.theme.accentSubtle : "#e0e7ff"
                }

                Tag {
                    theme: card.theme
                    text: qsTr("Archived")
                    visible: card.isArchived
                    textColor: card.theme ? card.theme.textSecondary : "#64748b"
                    fillColor: card.theme ? card.theme.surfaceHover : "#f1f5f9"
                }
            }

            // Previews arrive as plain text from the core; rendering them as
            // plain text keeps any stray markup in a note body inert.
            Label {
                text: card.snippet
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: 12
                lineHeight: 1.25
                color: card.theme ? card.theme.textSecondary : "#64748b"
                Layout.fillWidth: true
                visible: card.snippet.length > 0
            }

            Flow {
                Layout.fillWidth: true
                spacing: 4
                visible: card.tags.length > 0

                Repeater {
                    model: card.tags.slice(0, 4)
                    delegate: Tag {
                        required property string modelData
                        theme: card.theme
                        text: "#" + modelData
                        textColor: card.theme ? card.theme.textSecondary : "#64748b"
                        fillColor: card.theme ? card.theme.surfaceHover : "#f1f5f9"
                    }
                }

                Tag {
                    theme: card.theme
                    text: "+" + (card.tags.length - 4)
                    visible: card.tags.length > 4
                    textColor: card.theme ? card.theme.textMuted : "#94a3b8"
                    fillColor: card.theme ? card.theme.surfaceHover : "#f1f5f9"
                }
            }
        }

        StyledButton {
            text: qsTr("Bring here")
            theme: card.theme
            variant: "ghost"
            implicitHeight: 28
            padding: 4
            leftPadding: 10
            rightPadding: 10
            focusPolicy: Qt.NoFocus
            // Only the row being acted on needs the recovery action; showing it
            // on every row turns the list into a wall of buttons.
            // Kept in the layout at zero opacity: toggling visibility would
            // reflow the note text every time the pointer crosses a row.
            opacity: card.hovered || card.highlighted || card.activeFocus ? 1 : 0
            enabled: opacity > 0
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 10
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Move this note's window to the current screen")
            onClicked: card.bringHereRequested()

            Behavior on opacity {
                NumberAnimation { duration: card.theme ? card.theme.animShort : 120 }
            }
        }
    }
}
