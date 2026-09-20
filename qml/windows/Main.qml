pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BetterNotes.App

ApplicationWindow {
    id: window
    width: 640
    height: 480
    minimumWidth: 400
    minimumHeight: 300
    visible: true
    title: applicationInfo.name() + qsTr(" — All notes")
    property alias libraryBackend: backend
    property var noteWindows: ({})
    property string windowError: ""

    ApplicationInfo { id: applicationInfo }
    NotesBackend { id: backend; objectName: "notesBackend" }
    Component {
        id: stickyComponent
        StickyNote {
            onSaved: backend.reload()
            onDismissed: function(id) { window.releaseWindow(id) }
            onQuitRequested: window.close()
            onLibraryRequested: { window.showNormal(); window.requestActivate() }
        }
    }

    function initialize() {
        if (!backend.initialize()) return
        const ids = backend.restoreIds
        const errors = []
        for (let i = 0; i < ids.length; ++i) {
            if (!openNote(ids[i])) errors.push(windowError)
        }
        windowError = errors.join("\n")
    }
    Component.onCompleted: initialize()

    function openNote(id, recover) {
        let sticky = noteWindows[id]
        if (!sticky) {
            sticky = stickyComponent.createObject(window, {noteId: id}) as StickyNote
            if (!sticky) {
                windowError = qsTr("Could not create the note window. See Qt diagnostics.")
                return null
            }
            if (!sticky.present(window.screen)) {
                windowError = sticky.editorBackend.errorMessage
                sticky.destroy()
                return null
            }
            noteWindows[id] = sticky
        }
        windowError = ""
        if (recover) sticky.recover(window.screen)
        else {
            if (sticky.visibility === Window.Minimized) sticky.showNormal()
            sticky.requestActivate()
        }
        return sticky
    }

    function createNote() {
        if (backend.createNote()) return openNote(backend.currentId)
        return null
    }

    function releaseWindow(id) {
        const sticky = noteWindows[id]
        delete noteWindows[id]
        if (sticky) sticky.destroy()
    }

    onClosing: function(close) {
        const ids = Object.keys(noteWindows)
        // Save every editor before closing any window. A failure keeps all drafts.
        for (let i = 0; i < ids.length; ++i) {
            if (!noteWindows[ids[i]].prepareQuit()) {
                openNote(ids[i])
                windowError = qsTr("A note could not be saved. Resolve its error before quitting.")
                close.accepted = false
                return
            }
        }
        for (let i = 0; i < ids.length; ++i) {
            const sticky = noteWindows[ids[i]]
            sticky.retiring = true
            sticky.close()
        }
    }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            Button { text: qsTr("New note"); enabled: backend.ready; onClicked: window.createNote() }
            Button { text: qsTr("Refresh list"); enabled: backend.ready; onClicked: backend.reload() }
            Item { Layout.fillWidth: true }
            Button { text: qsTr("Quit"); onClicked: window.close() }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        Label {
            text: window.windowError || backend.errorMessage
            visible: text.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Accessible.role: Accessible.AlertMessage
        }
        Button { text: qsTr("Retry opening"); visible: !backend.ready; onClicked: window.initialize() }
        Label {
            text: qsTr("Open a note to edit it in its own window. Bring here recovers a misplaced window.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Label { visible: backend.ready && backend.titles.length === 0; text: qsTr("Create your first note.") }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ListView {
                id: notesList
                model: backend.titles
                activeFocusOnTab: true
                Keys.onReturnPressed: { if (currentIndex >= 0) window.openNote(backend.noteIds[currentIndex]) }
                delegate: ItemDelegate {
                    id: noteDelegate
                    required property int index
                    required property string modelData
                    width: ListView.view.width
                    highlighted: ListView.isCurrentItem
                    onClicked: { notesList.currentIndex = index; window.openNote(backend.noteIds[index]) }
                    contentItem: RowLayout {
                        Label {
                            text: noteDelegate.modelData.trim().length ? noteDelegate.modelData : qsTr("Untitled note")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Button { text: qsTr("Bring here"); onClicked: window.openNote(backend.noteIds[noteDelegate.index], true) }
                    }
                }
            }
        }
    }
    Shortcut { sequences: [StandardKey.New]; context: Qt.WindowShortcut; enabled: backend.ready; onActivated: window.createNote() }
    Shortcut { sequences: [StandardKey.Quit]; context: Qt.WindowShortcut; onActivated: window.close() }
}
