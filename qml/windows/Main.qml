pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BetterNotes.App

ApplicationWindow {
    id: window
    width: 880
    height: 580
    minimumWidth: 600
    minimumHeight: 400
    visible: true
    title: applicationInfo.name()

    ApplicationInfo { id: applicationInfo }
    NotesBackend { id: backend; objectName: "notesBackend" }

    Component.onCompleted: backend.initialize()
    onClosing: function(close) {
        // Qt's QML metadata exposes inputMethod as QObject, without its methods.
        // qmllint disable missing-property
        Qt.inputMethod.commit()
        // qmllint enable missing-property
        titleEditor.focus = false
        contentEditor.focus = false
        autosave.stop()
        close.accepted = backend.save()
    }

    Timer {
        id: autosave
        interval: 500
        repeat: false
        onTriggered: backend.save()
    }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            Button {
                text: qsTr("New note")
                objectName: "newNoteButton"
                enabled: backend.ready
                onClicked: {
                    if (backend.createNote()) titleEditor.forceActiveFocus()
                }
            }
            Button {
                text: qsTr("Delete")
                enabled: backend.currentIndex >= 0
                onClicked: deleteDialog.open()
            }
            Button {
                text: qsTr("Reload")
                enabled: backend.ready
                onClicked: {
                    if (backend.dirty) reloadDialog.open()
                    else backend.reload()
                }
            }
            Item { Layout.fillWidth: true }
            Label {
                text: !backend.ready ? qsTr("Unavailable")
                    : backend.dirty ? qsTr("Unsaved changes")
                    : qsTr("Saved")
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        RowLayout {
            visible: backend.errorMessage.length > 0
            Layout.fillWidth: true
            Label {
                text: backend.errorMessage
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Accessible.role: Accessible.AlertMessage
            }
            Button {
                text: backend.ready ? qsTr("Save again") : qsTr("Retry opening")
                onClicked: {
                    if (backend.ready) backend.save()
                    else backend.initialize()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 16

            ScrollView {
                Layout.preferredWidth: 210
                Layout.fillHeight: true
                clip: true
                ListView {
                    id: notesList
                    objectName: "notesList"
                    model: backend.titles
                    currentIndex: backend.currentIndex
                    keyNavigationEnabled: false
                    activeFocusOnTab: true
                    Keys.onUpPressed: {
                        if (currentIndex > 0) backend.selectNote(currentIndex - 1)
                    }
                    Keys.onDownPressed: {
                        if (currentIndex + 1 < count) backend.selectNote(currentIndex + 1)
                    }
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: ItemDelegate {
                        id: noteDelegate
                        required property int index
                        required property string modelData
                        width: ListView.view.width
                        highlighted: index === backend.currentIndex
                        contentItem: Label {
                            text: noteDelegate.modelData.trim().length > 0 ? noteDelegate.modelData : qsTr("Untitled note")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                        }
                        onClicked: backend.selectNote(index)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Label {
                    visible: backend.currentIndex < 0
                    text: backend.ready ? qsTr("Create a note or select one from the list.")
                        : qsTr("Unable to open your notes. See the error above.")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                TextField {
                    id: titleEditor
                    objectName: "titleEditor"
                    Layout.fillWidth: true
                    enabled: backend.currentIndex >= 0
                    placeholderText: qsTr("Title")
                    Accessible.name: qsTr("Note title")
                    text: backend.draftTitle
                    selectByMouse: true
                    onTextEdited: {
                        backend.editTitle(text)
                        autosave.restart()
                    }
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    TextArea {
                        id: contentEditor
                        objectName: "contentEditor"
                        enabled: backend.currentIndex >= 0
                        placeholderText: qsTr("Write your note…")
                        Accessible.name: qsTr("Note content")
                        text: backend.draftContent
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        // TextEdit.textEdited requires Qt 6.9. This guard also
                        // supports older Qt 6 and ignores changes from selection.
                        onTextChanged: {
                            if (text !== backend.draftContent) {
                                backend.editContent(text)
                                autosave.restart()
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        anchors.centerIn: parent
        title: qsTr("Delete this note?")
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        Label { text: qsTr("The note and any unsaved edits will be permanently deleted.") }
        onAccepted: backend.deleteNote()
    }

    Dialog {
        id: reloadDialog
        anchors.centerIn: parent
        title: qsTr("Discard unsaved changes?")
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        Label { text: qsTr("Reload the saved notes and discard this draft?") }
        onAccepted: backend.reload()
    }

    Shortcut {
        sequences: [StandardKey.New]
        enabled: backend.ready && !deleteDialog.visible && !reloadDialog.visible
        onActivated: {
            if (backend.createNote()) titleEditor.forceActiveFocus()
        }
    }
    Shortcut { sequences: [StandardKey.Save]; onActivated: backend.save() }
    Shortcut { sequences: [StandardKey.Quit]; onActivated: window.close() }
}
