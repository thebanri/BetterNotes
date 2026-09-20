pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BetterNotes.App
import "../themes" as Themes
import "../components" as UI

ApplicationWindow {
    id: window
    width: 640
    height: 480
    minimumWidth: 400
    minimumHeight: 300
    visible: true
    title: applicationInfo.name() + qsTr(" — All notes")
    color: theme.windowBackground
    property alias libraryBackend: backend
    property alias theme: theme
    property var noteWindows: ({})
    property string windowError: ""

    Themes.Theme { id: theme; themeMode: backend.themeMode }
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

    header: Rectangle {
        height: 48
        color: theme.surface
        border.width: 1
        border.color: theme.border

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Label {
                text: applicationInfo.name()
                font.pixelSize: 15
                font.weight: Font.Bold
                color: theme.textPrimary
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 20
                color: theme.border
                Layout.leftMargin: 4
                Layout.rightMargin: 4
            }

            UI.StyledButton {
                text: qsTr("New note")
                theme: window.theme
                variant: "accent"
                enabled: backend.ready
                onClicked: window.createNote()
            }

            UI.StyledButton {
                text: qsTr("Refresh")
                theme: window.theme
                variant: "ghost"
                enabled: backend.ready
                onClicked: backend.reload()
            }

            Item { Layout.fillWidth: true }

            UI.StyledButton {
                text: {
                    if (backend.themeMode === "light") return "☀️ " + qsTr("Light")
                    if (backend.themeMode === "dark") return "🌙 " + qsTr("Dark")
                    return "🖥️ " + qsTr("System")
                }
                theme: window.theme
                variant: "ghost"
                onClicked: {
                    if (backend.themeMode === "system") backend.setThemeMode("light")
                    else if (backend.themeMode === "light") backend.setThemeMode("dark")
                    else backend.setThemeMode("system")
                }
            }

            UI.StyledButton {
                text: qsTr("Quit")
                theme: window.theme
                variant: "ghost"
                onClicked: window.close()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Rectangle {
            visible: window.windowError.length > 0 || backend.errorMessage.length > 0
            Layout.fillWidth: true
            implicitHeight: errorRow.implicitHeight + 16
            radius: theme.radiusSm
            color: theme.dangerSubtle
            border.width: 1
            border.color: theme.danger

            RowLayout {
                id: errorRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                Label {
                    text: window.windowError || backend.errorMessage
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    color: theme.danger
                    Accessible.role: Accessible.AlertMessage
                }
            }
        }

        UI.StyledButton {
            text: qsTr("Retry opening")
            theme: window.theme
            variant: "accent"
            visible: !backend.ready
            onClicked: window.initialize()
        }

        Label {
            text: qsTr("Open a note to edit it in its own window. Bring here recovers a misplaced window.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pixelSize: 12
            color: theme.textSecondary
        }

        Rectangle {
            visible: backend.ready && backend.titles.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: theme.radiusMd
            color: theme.surface
            border.width: 1
            border.color: theme.border

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12

                Label {
                    text: "📝"
                    font.pixelSize: 36
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("No notes yet")
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("Create your first note to capture ideas and keep them on your desktop.")
                    font.pixelSize: 13
                    color: theme.textSecondary
                    Layout.alignment: Qt.AlignHCenter
                }
                UI.StyledButton {
                    text: qsTr("Create note")
                    theme: window.theme
                    variant: "accent"
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: window.createNote()
                }
            }
        }

        ScrollView {
            visible: backend.titles.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: notesList
                model: backend.titles
                spacing: 6
                activeFocusOnTab: true
                Keys.onReturnPressed: { if (currentIndex >= 0) window.openNote(backend.noteIds[currentIndex]) }
                delegate: UI.NoteCard {
                    id: noteDelegate
                    required property int index
                    required property string modelData
                    theme: window.theme
                    noteTitle: modelData
                    highlighted: ListView.isCurrentItem
                    onClicked: {
                        notesList.currentIndex = index
                        window.openNote(backend.noteIds[index])
                    }
                    onBringHereRequested: window.openNote(backend.noteIds[noteDelegate.index], true)
                }
            }
        }
    }
    Shortcut { sequences: [StandardKey.New]; context: Qt.WindowShortcut; enabled: backend.ready; onActivated: window.createNote() }
    Shortcut { sequences: [StandardKey.Quit]; context: Qt.WindowShortcut; onActivated: window.close() }
}
