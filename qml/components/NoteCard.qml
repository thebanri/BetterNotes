import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../themes"

ItemDelegate {
    id: card

    property Theme theme: null
    property string noteTitle: ""
    property string snippet: ""
    property bool isPinned: false
    property bool isArchived: false
    property int priority: 0
    signal bringHereRequested()

    implicitWidth: ListView.view ? ListView.view.width : 280
    implicitHeight: card.snippet.length > 0 ? 58 : 48
    padding: 0

    background: Rectangle {
        radius: card.theme ? card.theme.radiusMd : 6
        color: {
            if (card.down) return card.theme ? card.theme.surfaceActive : "#e2e8f0"
            if (card.hovered || card.highlighted) return card.theme ? card.theme.surfaceHover : "#f1f5f9"
            return card.theme ? card.theme.surface : "#ffffff"
        }
        border.width: 1
        border.color: {
            if (card.activeFocus) return card.theme ? card.theme.accent : "#6366f1"
            if (card.isPinned) return card.theme ? card.theme.accent : "#818cf8"
            if (card.highlighted) return card.theme ? card.theme.accentSubtle : "#cbd5e1"
            return card.theme ? card.theme.border : "#e2e8f0"
        }

        Behavior on color {
            ColorAnimation { duration: card.theme ? card.theme.animShort : 100 }
        }
    }

    contentItem: RowLayout {
        spacing: 10
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 8

        Rectangle {
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: {
                if (card.priority === 3) return card.theme ? card.theme.danger : "#ef4444"
                if (card.priority === 2) return card.theme ? card.theme.warning : "#f59e0b"
                if (card.isPinned) return card.theme ? card.theme.accent : "#6366f1"
                return card.theme ? card.theme.textSecondary : "#94a3b8"
            }
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    text: "📌"
                    font.pixelSize: 11
                    visible: card.isPinned
                    Layout.alignment: Qt.AlignVCenter
                }

                Label {
                    text: card.noteTitle.trim().length ? card.noteTitle : qsTr("Untitled note")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: card.theme ? card.theme.textPrimary : "#0f172a"
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Label {
                    text: {
                        if (card.priority === 3) return qsTr("High")
                        if (card.priority === 2) return qsTr("Med")
                        if (card.priority === 1) return qsTr("Low")
                        return ""
                    }
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    visible: card.priority > 0
                    padding: 3
                    color: {
                        if (card.priority === 3) return card.theme ? card.theme.danger : "#ef4444"
                        if (card.priority === 2) return card.theme ? card.theme.warning : "#f59e0b"
                        return card.theme ? card.theme.textSecondary : "#64748b"
                    }
                    background: Rectangle {
                        radius: 4
                        color: {
                            if (card.priority === 3) return card.theme ? card.theme.dangerSubtle : "#fee2e2"
                            if (card.priority === 2) return card.theme ? card.theme.warningSubtle : "#fef3c7"
                            return card.theme ? card.theme.surfaceHover : "#f1f5f9"
                        }
                    }
                    Layout.alignment: Qt.AlignVCenter
                }

                Label {
                    text: "📦 " + qsTr("Archived")
                    font.pixelSize: 10
                    visible: card.isArchived
                    color: card.theme ? card.theme.textSecondary : "#94a3b8"
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            Label {
                text: card.snippet
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: 11
                color: card.theme ? card.theme.textSecondary : "#64748b"
                Layout.fillWidth: true
                visible: card.snippet.length > 0
            }
        }

        StyledButton {
            text: qsTr("Bring here")
            theme: card.theme
            variant: "ghost"
            implicitHeight: 28
            padding: 4
            leftPadding: 8
            rightPadding: 8
            Layout.alignment: Qt.AlignVCenter
            onClicked: card.bringHereRequested()
        }
    }
}
