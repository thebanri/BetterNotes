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
        for (let i = 0; i < ids.length; ++i) {
            if (!openNote(ids[i])) errors.push(windowError)
        }
        windowError = errors.join("\n")
        if (applicationInfo.startQuickCapture()) {
            openQuickCapture()
        }
    }
    Component.onCompleted: initialize()

    // activate defaults to true; pass false to reveal a note without pulling it
    // above other windows or stealing keyboard focus.
    function openNote(id, recover, activate) {
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
        if (recover) {
            sticky.recover(window.screen)
        } else if (sticky.visibility === Window.Minimized) {
            sticky.showNormal()
            if (activate !== false) sticky.requestActivate()
        } else if (!sticky.visible) {
            sticky.show()
            if (activate !== false) sticky.requestActivate()
        } else if (activate !== false) {
            sticky.requestActivate()
        }
        // A note that is already on screen is left untouched when activate is
        // false: any show/raise call on it would restack it above other apps.
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

    // Reveals notes that are not on screen and changes nothing about the ones
    // that already are. Wayland gives a client no way to restack itself -- the
    // stays-on-bottom hint is ignored and lower() does nothing -- so any show()
    // or raise() here would push the whole board in front of other windows and
    // there would be no way to put it back.
    function showAllNotes() {
        const allIds = backend.noteIds
        for (let i = 0; i < allIds.length; ++i) {
            const sticky = noteWindows[allIds[i]]
            if (!sticky) openNote(allIds[i], false, false)
            else if (sticky.visibility === Window.Minimized) sticky.showNormal()
            else if (!sticky.visible) sticky.show()
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
        // If system tray is available or there are sticky notes on desktop, keep running in background!
        if (systemTray.available || ids.length > 0) {
            close.accepted = false
            window.hide()
            return
        }
        for (let i = 0; i < ids.length; ++i) {
            const sticky = noteWindows[ids[i]]
            sticky.retiring = true
            sticky.close()
        }
    }

    // Row counts for the filter chips. These read the list properties directly
    // so the bindings refresh with the model.
    function countNotes(kind) {
        let total = 0
        for (let i = 0; i < backend.titles.length; ++i) {
            const pinned = backend.pinnedStates[i] === "true"
            const archived = backend.archivedStates[i] === "true"
            if (kind === "pinned" ? pinned : (kind === "archived" ? archived : !archived)) total += 1
        }
        return total
    }

    function noteTagsAt(index) {
        const joined = backend.noteTags[index] || ""
        return joined.length > 0 ? joined.split(",") : []
    }

    function cycleThemeMode() {
        if (backend.themeMode === "system") backend.setThemeMode("light")
        else if (backend.themeMode === "light") backend.setThemeMode("dark")
        else backend.setThemeMode("system")
    }

    header: Rectangle {
        height: 56
        color: theme.surface

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: theme.border
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 12
            spacing: 8

            Label {
                text: applicationInfo.name()
                font.pixelSize: 16
                font.weight: Font.Bold
                color: theme.textPrimary
            }

            UI.Tag {
                theme: window.theme
                text: backend.noteIds.length === 1 ? qsTr("1 note") : qsTr("%1 notes").arg(backend.noteIds.length)
                visible: backend.ready
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            UI.StyledButton {
                iconName: "library"
                theme: window.theme
                variant: "ghost"
                implicitWidth: 32
                implicitHeight: 32
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Command palette (Ctrl+K)")
                onClicked: commandPalette.open()
            }

            UI.StyledButton {
                iconName: "palette"
                theme: window.theme
                variant: "ghost"
                implicitWidth: 32
                implicitHeight: 32
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: {
                    if (backend.themeMode === "light") return qsTr("Theme: Light — click for Dark")
                    if (backend.themeMode === "dark") return qsTr("Theme: Dark — click to follow the system")
                    return qsTr("Theme: System — click for Light")
                }
                onClicked: window.cycleThemeMode()
            }

            UI.StyledButton {
                iconName: "x"
                theme: window.theme
                variant: "ghost"
                implicitWidth: 32
                implicitHeight: 32
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: systemTray.available || Object.keys(window.noteWindows).length > 0
                    ? qsTr("Close the library — notes keep running")
                    : qsTr("Quit")
                onClicked: window.close()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Rectangle {
            visible: window.windowError.length > 0 || backend.errorMessage.length > 0
            Layout.fillWidth: true
            implicitHeight: errorRow.implicitHeight + 16
            radius: theme.radiusMd
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
                Layout.preferredHeight: 34
                leftPadding: 32
                rightPadding: 32
                placeholderText: qsTr("Search titles, content and tags…")
                Accessible.name: qsTr("Search notes")
                theme: window.theme
                onTextChanged: {
                    window.searchFilter = text.trim()
                    if (window.searchFilter.length > 0) {
                        backend.search(window.searchFilter)
                    }
                }
                Keys.onEscapePressed: clear()

                UI.AppIcon {
                    name: "search"
                    size: 15
                    color: theme.textMuted
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                }

                UI.StyledButton {
                    iconName: "x"
                    iconSize: 12
                    theme: window.theme
                    variant: "ghost"
                    implicitWidth: 22
                    implicitHeight: 22
                    padding: 0
                    focusPolicy: Qt.NoFocus
                    visible: searchField.text.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Clear search")
                    onClicked: searchField.clear()
                }
            }

            UI.StyledButton {
                text: qsTr("New note")
                iconName: "plus"
                iconSize: 14
                theme: window.theme
                variant: "accent"
                implicitHeight: 34
                enabled: backend.ready
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Create a note (Ctrl+N)")
                onClicked: window.createNote()
            }

            UI.StyledButton {
                text: qsTr("Show all")
                theme: window.theme
                variant: "secondary"
                implicitHeight: 34
                enabled: backend.ready && backend.noteIds.length > 0
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Bring back notes that are closed or minimised, leaving the ones already on screen where they are")
                onClicked: window.showAllNotes()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: backend.ready && window.searchFilter.length === 0

            Repeater {
                model: [
                    {key: "all", label: qsTr("All")},
                    {key: "pinned", label: qsTr("Pinned")},
                    {key: "archived", label: qsTr("Archived")}
                ]
                delegate: UI.StyledButton {
                    required property var modelData
                    text: modelData.label + "  " + window.countNotes(modelData.key)
                    theme: window.theme
                    variant: window.filterTab === modelData.key ? "accent" : "ghost"
                    implicitHeight: 28
                    padding: 4
                    leftPadding: 12
                    rightPadding: 12
                    onClicked: window.filterTab = modelData.key
                }
            }

            Item { Layout.fillWidth: true }

            UI.StyledButton {
                text: qsTr("Hide all")
                theme: window.theme
                variant: "ghost"
                implicitHeight: 28
                padding: 4
                leftPadding: 10
                rightPadding: 10
                enabled: Object.keys(window.noteWindows).length > 0
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Minimise every open note window")
                onClicked: window.hideAllNotes()
            }
        }

        // Tags wrap instead of overflowing the row when a database has many.
        Flow {
            Layout.fillWidth: true
            spacing: 4
            visible: backend.ready && backend.allTags.length > 0 && window.searchFilter.length === 0

            Repeater {
                model: backend.allTags
                delegate: UI.StyledButton {
                    required property string modelData
                    text: "#" + modelData
                    theme: window.theme
                    variant: "ghost"
                    implicitHeight: 24
                    padding: 2
                    leftPadding: 8
                    rightPadding: 8
                    font.pixelSize: 11
                    onClicked: searchField.text = modelData
                }
            }
        }

        Label {
            text: window.searchFilter.length > 0
                ? qsTr("Search results for “%1”").arg(window.searchFilter)
                : qsTr("Select a note to open its window. “Bring here” recovers one that is off-screen.")
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            Layout.fillWidth: true
            font.pixelSize: 12
            color: theme.textSecondary
            visible: backend.ready
        }

        Rectangle {
            visible: backend.ready && ((window.searchFilter.length === 0 && backend.titles.length === 0) || (window.searchFilter.length > 0 && backend.searchResultIds.length === 0))
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: theme.radiusLg
            color: theme.surface
            border.width: 1
            border.color: theme.border

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(360, parent.width - 48)
                spacing: 10

                UI.AppIcon {
                    name: window.searchFilter.length > 0 ? "search" : "library"
                    size: 32
                    strokeWidth: 1.5
                    color: theme.textMuted
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: window.searchFilter.length > 0 ? qsTr("No matching notes") : qsTr("No notes yet")
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: window.searchFilter.length > 0
                        ? qsTr("Try another term, or check the archived filter.")
                        : qsTr("Create your first note to keep it on your desktop.")
                    font.pixelSize: 13
                    color: theme.textSecondary
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
                UI.StyledButton {
                    text: qsTr("Create note")
                    iconName: "plus"
                    iconSize: 14
                    theme: window.theme
                    variant: "accent"
                    visible: window.searchFilter.length === 0
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: window.createNote()
                }
            }
        }

        ListView {
            id: notesList
            visible: (window.searchFilter.length === 0 && backend.titles.length > 0) || (window.searchFilter.length > 0 && backend.searchResultIds.length > 0)
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: window.searchFilter.length > 0 ? backend.searchResultIds : backend.titles
            spacing: 8
            activeFocusOnTab: true
            boundsBehavior: Flickable.StopAtBounds
            // Leave the scrollbar its own gutter so it never sits on a card.
            rightMargin: 10
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                anchors.right: parent.right
            }

            function idAt(index) {
                return window.searchFilter.length > 0 ? backend.searchResultIds[index] : backend.noteIds[index]
            }

            Keys.onReturnPressed: {
                if (currentIndex >= 0) window.openNote(idAt(currentIndex))
            }

            delegate: UI.NoteCard {
                id: noteDelegate
                required property int index
                required property string modelData
                theme: window.theme
                noteTitle: window.searchFilter.length > 0
                    ? (backend.searchResultTitles[index] || qsTr("Untitled note"))
                    : modelData
                snippet: window.searchFilter.length > 0
                    ? (backend.searchResultSnippets[index] || "")
                    : (backend.snippets[index] || "")
                tags: window.searchFilter.length > 0 ? [] : window.noteTagsAt(index)
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
                    window.openNote(notesList.idAt(index))
                }
                onBringHereRequested: window.openNote(notesList.idAt(noteDelegate.index), true)
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
        visible: false
        icon.name: "accessories-notes"
        tooltip: applicationInfo.name()

        onActivated: function(reason) {
            if (reason === Platform.SystemTrayIcon.Trigger) {
                if (window.visible) {
                    window.hide()
                } else {
                    window.showNormal()
                    window.requestActivate()
                }
            } else if (reason === Platform.SystemTrayIcon.Context) {
                trayMenu.open()
            }
        }

        menu: Platform.Menu {
            id: trayMenu
            visible: false
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
        id: trayTimer
        interval: 300
        running: true
        repeat: false
        onTriggered: {
            systemTray.visible = systemTray.available
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
