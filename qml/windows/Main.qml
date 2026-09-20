pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import BetterNotes.App
import "../themes" as Themes
import "../components" as UI

ApplicationWindow {
    id: window
    width: 640
    height: 480
    minimumWidth: 400
    minimumHeight: 300
    visible: !applicationInfo.startInBackground()
    title: applicationInfo.name() + qsTr(" — All notes")
    color: theme.windowBackground
    property alias libraryBackend: backend
    property alias theme: theme
    property var noteWindows: ({})
    property string windowError: ""
    property string filterTab: "all"
    property string searchFilter: ""
    property var quickCaptureWindow: null

    Themes.Theme { id: theme; themeMode: backend.themeMode }
    ApplicationInfo { id: applicationInfo }
    NotesBackend { id: backend; objectName: "notesBackend" }
    Component {
        id: stickyComponent
        StickyNote {
            onSaved: backend.reload()
            onDismissed: function(id) { window.releaseWindow(id) }
            onQuitRequested: window.quitApplication()
            onLibraryRequested: { window.showNormal(); window.requestActivate() }
            onNewNoteRequested: window.createNote()
        }
    }
    Component {
        id: quickCaptureComponent
        QuickCapture {
            onNoteCreated: function(id) {
                backend.reload()
                window.openNote(id)
            }
        }
    }

    function initialize() {
        if (!backend.initialize()) return
        const ids = backend.restoreIds
        const errors = []
        if (ids.length > 0) {
            for (let i = 0; i < ids.length; ++i) {
                if (!openNote(ids[i])) errors.push(windowError)
            }
        } else if (backend.noteIds.length > 0) {
            // Restore existing notes directly as sticky notes on the desktop
            for (let i = 0; i < backend.noteIds.length; ++i) {
                if (!openNote(backend.noteIds[i])) errors.push(windowError)
            }
        }
        windowError = errors.join("\n")
        if (applicationInfo.startQuickCapture()) {
            openQuickCapture()
        }
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

    function showAllNotes() {
        const allIds = backend.noteIds
        for (let i = 0; i < allIds.length; ++i) {
            openNote(allIds[i])
        }
        const ids = Object.keys(noteWindows)
        for (let i = 0; i < ids.length; ++i) {
            const sticky = noteWindows[ids[i]]
            if (sticky.visibility === Window.Minimized) sticky.showNormal()
            sticky.requestActivate()
        }
    }

    function hideAllNotes() {
        const ids = Object.keys(noteWindows)
        for (let i = 0; i < ids.length; ++i) {
            noteWindows[ids[i]].showMinimized()
        }
    }

    function openQuickCapture() {
        if (!quickCaptureWindow) {
            quickCaptureWindow = quickCaptureComponent.createObject(window, {theme: window.theme})
        }
        if (quickCaptureWindow) {
            quickCaptureWindow.showNormal()
            quickCaptureWindow.requestActivate()
        }
    }

    function quitApplication() {
        const ids = Object.keys(noteWindows)
        // Save every editor before closing any window. A failure keeps all drafts.
        for (let i = 0; i < ids.length; ++i) {
            if (!noteWindows[ids[i]].prepareQuit()) {
                openNote(ids[i])
                windowError = qsTr("A note could not be saved. Resolve its error before quitting.")
                return false
            }
        }
        for (let i = 0; i < ids.length; ++i) {
            const sticky = noteWindows[ids[i]]
            sticky.retiring = true
            sticky.close()
        }
        Qt.quit()
        return true
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
                text: qsTr("📌 Open all stickies")
                theme: window.theme
                variant: "secondary"
                enabled: backend.ready && backend.noteIds.length > 0
                onClicked: window.showAllNotes()
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

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: backend.ready

            UI.StyledTextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: qsTr("Search notes with FTS5 (Ctrl+K)...")
                theme: window.theme
                onTextChanged: {
                    window.searchFilter = text.trim()
                    if (window.searchFilter.length > 0) {
                        backend.search(window.searchFilter)
                    }
                }
            }

            UI.StyledButton {
                text: qsTr("Palette (Ctrl+K)")
                theme: window.theme
                variant: "ghost"
                onClicked: commandPalette.open()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: backend.ready && window.searchFilter.length === 0

            UI.StyledButton {
                text: qsTr("All")
                theme: window.theme
                variant: window.filterTab === "all" ? "accent" : "ghost"
                implicitHeight: 28
                padding: 4
                leftPadding: 10
                rightPadding: 10
                onClicked: window.filterTab = "all"
            }

            UI.StyledButton {
                text: "📌 " + qsTr("Pinned")
                theme: window.theme
                variant: window.filterTab === "pinned" ? "accent" : "ghost"
                implicitHeight: 28
                padding: 4
                leftPadding: 10
                rightPadding: 10
                onClicked: window.filterTab = "pinned"
            }

            UI.StyledButton {
                text: "📦 " + qsTr("Archived")
                theme: window.theme
                variant: window.filterTab === "archived" ? "accent" : "ghost"
                implicitHeight: 28
                padding: 4
                leftPadding: 10
                rightPadding: 10
                onClicked: window.filterTab = "archived"
            }

            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: backend.ready && backend.allTags.length > 0 && window.searchFilter.length === 0

            Label {
                text: qsTr("Tags:")
                font.pixelSize: 11
                color: theme.textSecondary
            }

            Repeater {
                model: backend.allTags
                delegate: UI.StyledButton {
                    required property string modelData
                    text: "#" + modelData
                    theme: window.theme
                    variant: "ghost"
                    implicitHeight: 24
                    padding: 2
                    leftPadding: 6
                    rightPadding: 6
                    onClicked: {
                        searchField.text = modelData
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        Label {
            text: window.searchFilter.length > 0 ?
                qsTr("Showing search results for '%1'").arg(window.searchFilter) :
                qsTr("Open a note to edit it in its own window. Bring here recovers a misplaced window.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pixelSize: 12
            color: theme.textSecondary
        }

        Rectangle {
            visible: backend.ready && ((window.searchFilter.length === 0 && backend.titles.length === 0) || (window.searchFilter.length > 0 && backend.searchResultIds.length === 0))
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
                    text: window.searchFilter.length > 0 ? "🔍" : "📝"
                    font.pixelSize: 36
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: window.searchFilter.length > 0 ? qsTr("No matching notes found") : qsTr("No notes yet")
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: window.searchFilter.length > 0 ?
                        qsTr("Try a different search term or check archived notes.") :
                        qsTr("Create your first note to capture ideas and keep them on your desktop.")
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
            visible: (window.searchFilter.length === 0 && backend.titles.length > 0) || (window.searchFilter.length > 0 && backend.searchResultIds.length > 0)
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: notesList
                model: window.searchFilter.length > 0 ? backend.searchResultIds : backend.titles
                spacing: 6
                activeFocusOnTab: true
                Keys.onReturnPressed: {
                    if (currentIndex >= 0) {
                        const targetId = window.searchFilter.length > 0 ? backend.searchResultIds[currentIndex] : backend.noteIds[currentIndex]
                        window.openNote(targetId)
                    }
                }
                delegate: UI.NoteCard {
                    id: noteDelegate
                    required property int index
                    required property string modelData
                    theme: window.theme
                    noteTitle: {
                        if (window.searchFilter.length > 0) {
                            return backend.searchResultTitles[index] || qsTr("Untitled note")
                        }
                        return modelData
                    }
                    snippet: {
                        if (window.searchFilter.length > 0) {
                            return backend.searchResultSnippets[index] || ""
                        }
                        return backend.snippets[index] || ""
                    }
                    isPinned: window.searchFilter.length === 0 && backend.pinnedStates[index] === "true"
                    isArchived: window.searchFilter.length === 0 && backend.archivedStates[index] === "true"
                    priority: window.searchFilter.length === 0 ? parseInt(backend.priorities[index] || "0") : 0
                    visible: {
                        if (window.searchFilter.length > 0) return true
                        const pinned = backend.pinnedStates[index] === "true"
                        const archived = backend.archivedStates[index] === "true"
                        if (window.filterTab === "pinned") return pinned
                        if (window.filterTab === "archived") return archived
                        return !archived
                    }
                    height: visible ? implicitHeight : 0
                    highlighted: ListView.isCurrentItem
                    onClicked: {
                        notesList.currentIndex = index
                        const targetId = window.searchFilter.length > 0 ? backend.searchResultIds[index] : backend.noteIds[index]
                        window.openNote(targetId)
                    }
                    onBringHereRequested: {
                        const targetId = window.searchFilter.length > 0 ? backend.searchResultIds[noteDelegate.index] : backend.noteIds[noteDelegate.index]
                        window.openNote(targetId, true)
                    }
                }
            }
        }
    }

    UI.CommandPalette {
        id: commandPalette
        theme: window.theme
        backend: window.libraryBackend
        onNoteSelected: function(id) { window.openNote(id) }
        onActionTriggered: function(action) {
            if (action === "new_note") window.createNote()
            else if (action === "quick_capture") window.openQuickCapture()
            else if (action === "show_all") window.showAllNotes()
            else if (action === "hide_all") window.hideAllNotes()
            else if (action === "toggle_theme") {
                if (backend.themeMode === "system") backend.setThemeMode("light")
                else if (backend.themeMode === "light") backend.setThemeMode("dark")
                else backend.setThemeMode("system")
            }
            else if (action === "diagnostics") diagnosticsDialog.open()
            else if (action === "export_json") {
                backend.exportNotesJson("betternotes_export.json")
                backend.sendNotification(qsTr("Export complete"), qsTr("Notes exported to betternotes_export.json"))
            }
            else if (action === "export_markdown") {
                backend.exportNotesMarkdown("betternotes_markdown_export")
                backend.sendNotification(qsTr("Export complete"), qsTr("Notes exported to betternotes_markdown_export"))
            }
        }
    }

    Platform.SystemTrayIcon {
        id: systemTray
        visible: systemTray.available
        icon.name: "accessories-notes"
        tooltip: applicationInfo.name()

        menu: Platform.Menu {
            Platform.MenuItem {
                text: qsTr("New note")
                enabled: backend.ready
                onTriggered: window.createNote()
            }
            Platform.MenuItem {
                text: qsTr("Quick capture")
                onTriggered: window.openQuickCapture()
            }
            Platform.MenuItem {
                text: qsTr("Search notes")
                onTriggered: {
                    window.showNormal()
                    window.requestActivate()
                    commandPalette.open()
                }
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: qsTr("Show all notes")
                onTriggered: window.showAllNotes()
            }
            Platform.MenuItem {
                text: qsTr("Hide all notes")
                onTriggered: window.hideAllNotes()
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: qsTr("Start at login")
                checkable: true
                checked: backend.autostartEnabled
                onTriggered: backend.setAutostart(!checked)
            }
            Platform.MenuItem {
                text: qsTr("Open library")
                onTriggered: {
                    window.showNormal()
                    window.requestActivate()
                }
            }
            Platform.MenuItem {
                text: qsTr("Desktop diagnostics")
                onTriggered: {
                    window.showNormal()
                    window.requestActivate()
                    diagnosticsDialog.open()
                }
            }
            Platform.MenuItem {
                text: qsTr("Export notes (JSON)")
                onTriggered: {
                    backend.exportNotesJson("betternotes_export.json")
                    backend.sendNotification(qsTr("Export complete"), qsTr("Notes exported to betternotes_export.json"))
                }
            }
            Platform.MenuSeparator {}
            Platform.MenuItem {
                text: qsTr("Quit")
                onTriggered: window.quitApplication()
            }
        }
    }

    Dialog {
        id: diagnosticsDialog
        title: qsTr("Desktop Environment & Diagnostics")
        modal: true
        standardButtons: Dialog.Close
        width: Math.min(520, window.width - 40)
        x: Math.round((window.width - width) / 2)
        y: Math.round((window.height - height) / 2)

        contentItem: ColumnLayout {
            spacing: 8
            TextArea {
                text: applicationInfo.diagnosticsReport()
                readOnly: true
                font.family: "monospace"
                font.pixelSize: 12
                wrapMode: TextEdit.Wrap
                color: window.theme.textPrimary
                background: Rectangle {
                    color: window.theme.surface
                    border.width: 1
                    border.color: window.theme.border
                    radius: 6
                }
            }
        }
    }

    Shortcut { sequences: [StandardKey.New]; context: Qt.WindowShortcut; enabled: backend.ready; onActivated: window.createNote() }
    Shortcut { sequences: [StandardKey.Quit]; context: Qt.WindowShortcut; onActivated: window.close() }
    Shortcut { sequences: ["Ctrl+K", "Ctrl+Shift+P"]; context: Qt.WindowShortcut; onActivated: commandPalette.open() }
    Shortcut { sequences: ["Ctrl+Alt+Space"]; onActivated: window.openQuickCapture() }

    Timer {
        id: reminderTimer
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (backend.ready) backend.checkReminders()
        }
    }

    Timer {
        id: ipcPollTimer
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            if (backend.ready) {
                let action = backend.pollIpcAction()
                if (action === "activate") {
                    if (window.visibility === Window.Minimized) window.showNormal()
                    window.requestActivate()
                } else if (action === "quick_capture") {
                    window.openQuickCapture()
                } else if (action.startsWith("open:")) {
                    let id = action.substring(5)
                    window.openNote(id)
                }
            }
        }
    }
}
