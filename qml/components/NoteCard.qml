import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../themes"

ItemDelegate {
    id: card

    property Theme theme: null
    property string noteTitle: ""
    signal bringHereRequested()

    implicitWidth: ListView.view ? ListView.view.width : 280
    implicitHeight: 48
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
            color: card.theme ? card.theme.accent : "#6366f1"
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
