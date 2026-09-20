pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BetterNotes.App
import "../themes" as Themes
import "../components" as UI

ApplicationWindow {
    id: captureWindow
    width: 400
    height: 260
    minimumWidth: 320
    minimumHeight: 200
    title: qsTr("BetterNotes — Quick Capture")
    color: theme.windowBackground
    flags: Qt.Window | Qt.WindowStaysOnTopHint

    property Themes.Theme theme: null
    property string activeScreenName: screen ? screen.name : ""
    signal noteCreated(string noteId)

    NotesBackend {
        id: captureBackend
        Component.onCompleted: captureBackend.initialize()
    }

    function saveAndClose() {
        const titleText = titleInput.text.trim()
        const bodyText = contentInput.text.trim()
        if (titleText.length === 0 && bodyText.length === 0) {
            captureWindow.close()
            return
        }
        if (captureBackend.createNote()) {
            captureBackend.editTitle(titleText.length > 0 ? titleText : qsTr("Quick capture"))
            captureBackend.editContent(bodyText)
            captureBackend.save()
            captureWindow.noteCreated(captureBackend.currentId)
        }
        captureWindow.close()
    }

    onVisibleChanged: {
        if (visible) {
            titleInput.text = ""
            contentInput.text = ""
            contentInput.forceActiveFocus()
        }
    }

    header: Rectangle {
        height: 38
        color: captureWindow.theme ? captureWindow.theme.surface : "#ffffff"
        border.width: 1
        border.color: captureWindow.theme ? captureWindow.theme.border : "#e2e8f0"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 6

            Label {
                text: "⚡ " + qsTr("Quick capture")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: captureWindow.theme ? captureWindow.theme.textPrimary : "#0f172a"
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Label {
                text: "Ctrl+Enter " + qsTr("to save")
                font.pixelSize: 11
                color: captureWindow.theme ? captureWindow.theme.textSecondary : "#64748b"
                Layout.alignment: Qt.AlignVCenter
            }

            UI.StyledButton {
                text: "✕"
                theme: captureWindow.theme
                variant: "ghost"
                implicitHeight: 26
                padding: 2
                leftPadding: 6
                rightPadding: 6
                onClicked: captureWindow.close()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        TextField {
            id: titleInput
            Layout.fillWidth: true
            placeholderText: qsTr("Note title (optional)...")
            font.pixelSize: 14
            font.weight: Font.Medium
            color: captureWindow.theme ? captureWindow.theme.textPrimary : "#0f172a"
            placeholderTextColor: captureWindow.theme ? captureWindow.theme.textSecondary : "#94a3b8"
            selectByMouse: true
            background: Rectangle {
                color: "transparent"
                border.width: titleInput.activeFocus ? 1 : 0
                border.color: captureWindow.theme ? captureWindow.theme.accent : "#6366f1"
                radius: 4
            }
            Keys.onReturnPressed: contentInput.forceActiveFocus()
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            TextArea {
                id: contentInput
                placeholderText: qsTr("Type thoughts, ideas, or paste clipboard text...")
                font.pixelSize: 13
                color: captureWindow.theme ? captureWindow.theme.textPrimary : "#0f172a"
                placeholderTextColor: captureWindow.theme ? captureWindow.theme.textSecondary : "#94a3b8"
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                background: Rectangle {
                    color: "transparent"
                }
                Keys.onReturnPressed: function(event) {
                    if (event.modifiers & Qt.ControlModifier) {
                        captureWindow.saveAndClose()
                        event.accepted = true
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            UI.StyledButton {
                text: qsTr("Paste from clipboard")
                theme: captureWindow.theme
                variant: "ghost"
                implicitHeight: 28
                onClicked: {
                    const text = captureBackend.getClipboardText()
                    if (text.length > 0) {
                        contentInput.insert(contentInput.cursorPosition, text)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            UI.StyledButton {
                text: qsTr("Cancel")
                theme: captureWindow.theme
                variant: "ghost"
                implicitHeight: 28
                onClicked: captureWindow.close()
            }

            UI.StyledButton {
                text: qsTr("Save note")
                theme: captureWindow.theme
                variant: "accent"
                implicitHeight: 28
                onClicked: captureWindow.saveAndClose()
            }
        }
    }

    Shortcut { sequence: "Escape"; context: Qt.WindowShortcut; onActivated: captureWindow.close() }
    Shortcut { sequence: "Ctrl+Return"; context: Qt.WindowShortcut; onActivated: captureWindow.saveAndClose() }
}
