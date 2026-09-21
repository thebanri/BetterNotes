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
    width: 960
    height: 620
    minimumWidth: 440
    minimumHeight: 360
    visible: !applicationInfo.startInBackground()
    title: applicationInfo.name() + qsTr(" — All notes")
    // Frameless: the window draws its own title bar and rounded frame.
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    property alias libraryBackend: backend
    property alias theme: theme
    property alias reminderEditorItem: reminderEditor
    property var noteWindows: ({})
    property string windowError: ""
    property string filterTab: "all"
    property string tagFilter: ""
    // noteWindows is a plain object, so bindings cannot see it change. Anything
    // that shows which notes are open also reads this counter.
    property int windowsRevision: 0
    property string searchFilter: ""
    property var quickCaptureWindow: null

    Themes.Theme { id: theme; themeMode: backend.themeMode }
    ApplicationInfo { id: applicationInfo }
    NotesBackend { id: backend; objectName: "notesBackend" }
    // Saves and restores note positions on KDE Plasma under Wayland, where the
    // app cannot see or set window positions itself.
    WindowPlacement {
        id: placementService
        onMoved: function(noteId, x, y) {
            const sticky = window.noteWindows[noteId]
            if (sticky) sticky.moveReported(x, y)
        }
    }
    Component {
        id: stickyComponent
        StickyNote {
            stayBelow: backend.notesStayBelow
            placement: placementService
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
            windowsRevision += 1
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
        placementService.forget(id)
        windowsRevision += 1
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

    // ---- Library data -----------------------------------------------------

    function noteTagsAt(index) {
        const joined = backend.noteTags[index] || ""
        return joined.length > 0 ? joined.split(",") : []
    }

    // Row counts for the sidebar. They read the list properties directly so
    // the bindings refresh with the model.
    function countNotes(kind) {
        let total = 0
        for (let i = 0; i < backend.titles.length; ++i) {
            const pinned = backend.pinnedStates[i] === "true"
            const archived = backend.archivedStates[i] === "true"
            if (kind === "reminders") {
                if ((backend.noteReminders[i] || "").length > 0) total += 1
            } else if (kind === "pinned" ? pinned && !archived : (kind === "archived" ? archived : !archived)) total += 1
        }
        return total
    }

    function countTag(tag) {
        let total = 0
        for (let i = 0; i < backend.titles.length; ++i) {
            if (backend.archivedStates[i] !== "true" && noteTagsAt(i).indexOf(tag) >= 0) total += 1
        }
        return total
    }

    // The cards to show: search results while searching, otherwise the notes
    // in the selected section, narrowed to the selected tag.
    readonly property var visibleNotes: {
        const rows = []
        const indexById = {}
        for (let i = 0; i < backend.noteIds.length; ++i) indexById[backend.noteIds[i]] = i
        function row(id, title, snippet) {
            const i = indexById[id]
            const known = i !== undefined
            return {
                id: id,
                title: title,
                snippet: snippet,
                tags: known ? window.noteTagsAt(i) : [],
                pinned: known && backend.pinnedStates[i] === "true",
                archived: known && backend.archivedStates[i] === "true",
                priority: known ? parseInt(backend.priorities[i] || "0") : 0,
                tint: known ? (backend.noteColors[i] || "yellow") : "yellow",
                reminder: known ? (backend.noteReminders[i] || "") : ""
            }
        }
        if (searchFilter.length > 0) {
            for (let k = 0; k < backend.searchResultIds.length; ++k) {
                rows.push(row(backend.searchResultIds[k], backend.searchResultTitles[k] || "", backend.searchResultSnippets[k] || ""))
            }
            return rows
        }
        for (let i = 0; i < backend.noteIds.length; ++i) {
            const note = row(backend.noteIds[i], backend.titles[i], backend.snippets[i] || "")
            if (filterTab === "archived" ? !note.archived : note.archived) continue
            if (filterTab === "pinned" && !note.pinned) continue
            if (filterTab === "reminders" && note.reminder.length === 0) continue
            if (tagFilter.length > 0 && note.tags.indexOf(tagFilter) < 0) continue
            rows.push(note)
        }
        return rows
    }

    readonly property string sectionTitle: {
        if (searchFilter.length > 0) return qsTr("Results for “%1”").arg(searchFilter)
        if (tagFilter.length > 0) return "#" + tagFilter
        if (filterTab === "pinned") return qsTr("Pinned")
        if (filterTab === "archived") return qsTr("Archive")
        if (filterTab === "reminders") return qsTr("Reminders")
        return qsTr("All notes")
    }

    function showSection(tab, tag) {
        filterTab = tab
        tagFilter = tag || ""
        searchField.text = ""
    }

    function cycleThemeMode() {
        if (backend.themeMode === "system") backend.setThemeMode("light")
        else if (backend.themeMode === "light") backend.setThemeMode("dark")
        else backend.setThemeMode("system")
    }

    // ---- Note actions -----------------------------------------------------

    // Every per-note action from the library. A note that is open in its own
    // window is changed through that window's editor, which owns the note's
    // revision; changing it behind the editor's back would make the editor's
    // next save fail with a conflict.
    function noteAction(id, action) {
        const sticky = noteWindows[id]
        if (action === "open") {
            openNote(id)
        } else if (action === "locate") {
            openNote(id, true)
        } else if (action === "copy") {
            if (sticky) sticky.flush()
            const text = backend.notePlainText(id)
            if (text.length > 0 && backend.copyToClipboard(text)) showToast(qsTr("Copied to the clipboard"))
        } else if (action === "pin" || action === "unpin") {
            const pinned = action === "pin"
            if (sticky) {
                if (sticky.editorBackend.setPinned(pinned)) sticky.flush()
            } else {
                backend.setNotePinned(id, pinned)
            }
        } else if (action === "archive" || action === "restore") {
            const archived = action === "archive"
            if (sticky) {
                if (sticky.editorBackend.setArchived(archived) && sticky.flush() && archived) {
                    // Archiving puts a note away, so its window goes too.
                    sticky.close()
                }
            } else {
                backend.setNoteArchived(id, archived)
            }
            if (archived) showToast(qsTr("Moved to the archive"))
        } else if (action === "reminder") {
            editReminder(id)
        } else if (action === "delete") {
            deleteDialog.noteId = id
            deleteDialog.open()
        }
    }

    // Reminders live beside the note, not in its text, so the library sets
    // them directly even while the note is open; an open note is told to
    // show the change.
    function editReminder(id) {
        const index = backend.noteIds.indexOf(id)
        reminderEditor.noteId = id
        reminderEditor.openFor(index >= 0 ? backend.titles[index] : "", backend.noteReminder(id))
    }

    function reminderChanged(id) {
        const sticky = noteWindows[id]
        if (sticky) sticky.refreshReminder()
    }

    function deleteNoteConfirmed(id) {
        const sticky = noteWindows[id]
        if (sticky) sticky.deleteConfirmed()
        else backend.deleteNoteById(id)
    }

    function showToast(message) {
        toast.text = message
        toast.shown = true
        toastTimer.restart()
    }

    // ---- Frame ------------------------------------------------------------

    readonly property bool maximized: window.visibility === Window.Maximized
    readonly property int frameRadius: maximized ? 0 : 14

    function toggleMaximized() {
        if (maximized) window.showNormal()
        else window.showMaximized()
    }

    background: Rectangle {
        radius: window.frameRadius
        color: theme.windowBackground
        border.width: window.maximized ? 0 : 1
        border.color: theme.border
    }

    // A frameless window moves by its empty chrome and resizes by its edges.
    component DragArea: Item {
        DragHandler {
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromAnything
            onActiveChanged: if (active) window.startSystemMove()
        }
        TapHandler {
            onDoubleTapped: window.toggleMaximized()
        }
    }

    component SidebarItem: ItemDelegate {
        id: item
        property string iconName: ""
        property int count: -1
        property bool selected: false
        Layout.fillWidth: true
        implicitHeight: 34
        leftPadding: 10
        rightPadding: 10
        focusPolicy: Qt.NoFocus
        background: Rectangle {
            radius: theme.radiusMd
            color: item.selected ? theme.accentSubtle : (item.hovered ? theme.surfaceHover : "transparent")
        }
        contentItem: RowLayout {
            spacing: 10
            UI.AppIcon {
                name: item.iconName
                size: 16
                color: item.selected ? theme.accent : theme.textSecondary
            }
            Label {
                text: item.text
                elide: Text.ElideRight
                font.pixelSize: 13
                font.weight: item.selected ? Font.DemiBold : Font.Normal
                color: item.selected ? theme.textPrimary : theme.textSecondary
                Layout.fillWidth: true
            }
            Label {
                visible: item.count >= 0
                text: item.count
                font.pixelSize: 11
                color: theme.textMuted
            }
        }
    }

    component WindowButton: UI.StyledButton {
        property string hint: ""
        theme: window.theme
        variant: "ghost"
        iconSize: 14
        implicitWidth: 32
        implicitHeight: 32
        padding: 0
        focusPolicy: Qt.NoFocus
        ToolTip.visible: hovered
        ToolTip.text: hint
        ToolTip.delay: 500
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: window.maximized ? 0 : 1
        spacing: 0

        // ---- Sidebar ------------------------------------------------------
        Rectangle {
            id: sidebar
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            radius: window.frameRadius
            color: theme.surfaceElevated
            visible: window.width >= 620

            // Square off the edge that meets the content area.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.radius
                color: parent.color
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: theme.border
            }

            DragArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 16
                spacing: 4

                RowLayout {
                    spacing: 10
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 12
                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 8
                        color: theme.accent
                        UI.AppIcon {
                            anchors.centerIn: parent
                            name: "sticky-note"
                            size: 16
                            color: theme.accentText
                        }
                    }
                    Label {
                        text: applicationInfo.name()
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: theme.textPrimary
                    }
                }

                UI.StyledButton {
                    text: qsTr("New note")
                    iconName: "plus"
                    iconSize: 15
                    theme: window.theme
                    variant: "accent"
                    implicitHeight: 36
                    enabled: backend.ready
                    Layout.fillWidth: true
                    Layout.bottomMargin: 12
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Create a note (Ctrl+N)")
                    ToolTip.delay: 500
                    onClicked: window.createNote()
                }

                SidebarItem {
                    text: qsTr("All notes")
                    iconName: "sticky-note"
                    count: window.countNotes("all")
                    selected: window.searchFilter.length === 0 && window.filterTab === "all" && window.tagFilter.length === 0
                    onClicked: window.showSection("all")
                }
                SidebarItem {
                    text: qsTr("Pinned")
                    iconName: "pin"
                    count: window.countNotes("pinned")
                    selected: window.searchFilter.length === 0 && window.filterTab === "pinned"
                    onClicked: window.showSection("pinned")
                }
                SidebarItem {
                    objectName: "remindersSection"
                    text: qsTr("Reminders")
                    iconName: "bell"
                    count: window.countNotes("reminders")
                    selected: window.searchFilter.length === 0 && window.filterTab === "reminders"
                    onClicked: window.showSection("reminders")
                }
                SidebarItem {
                    text: qsTr("Archive")
                    iconName: "archive"
                    count: window.countNotes("archived")
                    selected: window.searchFilter.length === 0 && window.filterTab === "archived"
                    onClicked: window.showSection("archived")
                }

                Label {
                    visible: backend.allTags.length > 0
                    text: qsTr("Tags")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    color: theme.textMuted
                    Layout.leftMargin: 10
                    Layout.topMargin: 16
                    Layout.bottomMargin: 2
                }

                ListView {
                    id: tagList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: backend.allTags
                    delegate: SidebarItem {
                        required property string modelData
                        width: tagList.width
                        text: modelData
                        iconName: "tag"
                        count: window.countTag(modelData)
                        selected: window.searchFilter.length === 0 && window.tagFilter === modelData
                        onClicked: window.showSection("all", modelData)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 6
                    Layout.bottomMargin: 6
                    color: theme.border
                }

                SidebarItem {
                    text: qsTr("Show all on desktop")
                    iconName: "eye"
                    enabled: backend.ready && backend.noteIds.length > 0
                    onClicked: window.showAllNotes()
                }
                SidebarItem {
                    text: qsTr("Hide all")
                    iconName: "eye-off"
                    enabled: window.windowsRevision >= 0 && Object.keys(window.noteWindows).length > 0
                    onClicked: window.hideAllNotes()
                }
            }
        }

        // ---- Content ------------------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Top bar: search, then settings and the window buttons.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 60

                DragArea { anchors.fill: parent }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 10
                    spacing: 6

                    UI.StyledButton {
                        visible: !sidebar.visible
                        iconName: "plus"
                        theme: window.theme
                        variant: "accent"
                        implicitWidth: 34
                        implicitHeight: 34
                        padding: 0
                        enabled: backend.ready
                        onClicked: window.createNote()
                    }

                    UI.StyledTextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.maximumWidth: 480
                        Layout.preferredHeight: 36
                        leftPadding: 34
                        rightPadding: 32
                        placeholderText: qsTr("Search notes…")
                        // Typing in the library searches straight away.
                        focus: true
                        Accessible.name: qsTr("Search notes")
                        theme: window.theme
                        enabled: backend.ready
                        background: Rectangle {
                            radius: 18
                            color: theme.surface
                            border.width: searchField.activeFocus ? 2 : 1
                            border.color: searchField.activeFocus ? theme.accent : theme.border
                        }
                        onTextChanged: {
                            window.searchFilter = text.trim()
                            if (window.searchFilter.length > 0) backend.search(window.searchFilter)
                        }
                        Keys.onEscapePressed: clear()
                        Keys.onDownPressed: noteGrid.forceActiveFocus()

                        UI.AppIcon {
                            name: "search"
                            size: 15
                            color: theme.textMuted
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        UI.StyledButton {
                            iconName: "x"
                            iconSize: 12
                            theme: window.theme
                            variant: "ghost"
                            implicitWidth: 24
                            implicitHeight: 24
                            padding: 0
                            focusPolicy: Qt.NoFocus
                            visible: searchField.text.length > 0
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: searchField.clear()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    WindowButton {
                        iconName: "library"
                        hint: qsTr("Command palette (Ctrl+K)")
                        onClicked: commandPalette.open()
                    }
                    WindowButton {
                        iconName: "settings"
                        hint: qsTr("Settings")
                        variant: settingsPopup.visible ? "accent" : "ghost"
                        onClicked: settingsPopup.open()
                    }
                    Rectangle {
                        implicitWidth: 1
                        implicitHeight: 18
                        color: theme.border
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                    }
                    WindowButton {
                        iconName: "minus"
                        hint: qsTr("Minimise")
                        onClicked: window.showMinimized()
                    }
                    WindowButton {
                        iconName: window.maximized ? "window-restore" : "window-maximize"
                        hint: window.maximized ? qsTr("Restore") : qsTr("Maximise")
                        onClicked: window.toggleMaximized()
                    }
                    WindowButton {
                        iconName: "x"
                        hint: systemTray.available || Object.keys(window.noteWindows).length > 0
                            ? qsTr("Close — notes keep running") : qsTr("Quit")
                        onClicked: window.close()
                    }
                }
            }

            // Section heading.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.bottomMargin: 12
                spacing: 10
                visible: backend.ready

                Label {
                    text: window.sectionTitle
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: theme.textPrimary
                    Layout.fillWidth: true
                }
                Label {
                    text: window.visibleNotes.length === 1 ? qsTr("1 note") : qsTr("%1 notes").arg(window.visibleNotes.length)
                    font.pixelSize: 12
                    color: theme.textMuted
                }
            }

            Rectangle {
                visible: window.windowError.length > 0 || backend.errorMessage.length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.bottomMargin: 12
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
                Layout.leftMargin: 24
                onClicked: window.initialize()
            }

            // Empty state.
            ColumnLayout {
                visible: backend.ready && window.visibleNotes.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                Item { Layout.fillHeight: true }
                UI.AppIcon {
                    name: window.searchFilter.length > 0 ? "search" : (window.filterTab === "archived" ? "archive" : "sticky-note")
                    size: 40
                    strokeWidth: 1.4
                    color: theme.textMuted
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: {
                        if (window.searchFilter.length > 0) return qsTr("No matching notes")
                        if (window.filterTab === "archived") return qsTr("The archive is empty")
                        if (window.filterTab === "pinned") return qsTr("No pinned notes")
                        if (window.tagFilter.length > 0) return qsTr("No notes with this tag")
                        return qsTr("No notes yet")
                    }
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: theme.textPrimary
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: {
                        if (window.searchFilter.length > 0) return qsTr("Try another word, or look in the archive.")
                        if (window.filterTab === "archived") return qsTr("Archived notes are kept here, out of the way.")
                        if (window.filterTab === "pinned") return qsTr("Pin a note to keep it at the top of the list.")
                        return qsTr("Create a note to keep it on your desktop.")
                    }
                    font.pixelSize: 13
                    color: theme.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    Layout.maximumWidth: 360
                    Layout.alignment: Qt.AlignHCenter
                }
                UI.StyledButton {
                    visible: window.filterTab === "all" && window.searchFilter.length === 0 && window.tagFilter.length === 0
                    text: qsTr("New note")
                    iconName: "plus"
                    iconSize: 14
                    theme: window.theme
                    variant: "accent"
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    onClicked: window.createNote()
                }
                Item { Layout.fillHeight: true }
            }

            // The notes.
            GridView {
                id: noteGrid
                visible: backend.ready && window.visibleNotes.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 18
                Layout.rightMargin: 8
                clip: true
                model: window.visibleNotes
                readonly property int columns: Math.max(1, Math.floor((width - 10) / 240))
                cellWidth: Math.floor((width - 10) / columns)
                cellHeight: 176
                bottomMargin: 18
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationWraps: false
                activeFocusOnTab: true
                currentIndex: -1
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Keys.onReturnPressed: if (currentIndex >= 0) window.noteAction(window.visibleNotes[currentIndex].id, "open")
                Keys.onDeletePressed: if (currentIndex >= 0) window.noteAction(window.visibleNotes[currentIndex].id, "delete")
                onActiveFocusChanged: if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: noteGrid.cellWidth
                    height: noteGrid.cellHeight

                    UI.NoteCard {
                        anchors.fill: parent
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 12
                        theme: window.theme
                        noteTitle: cell.modelData.title
                        snippet: cell.modelData.snippet
                        tags: cell.modelData.tags
                        isPinned: cell.modelData.pinned
                        isArchived: cell.modelData.archived
                        priority: cell.modelData.priority
                        tint: cell.modelData.tint
                        reminder: cell.modelData.reminder
                        onDesktop: window.windowsRevision >= 0 && !!window.noteWindows[cell.modelData.id]
                        current: noteGrid.activeFocus && noteGrid.currentIndex === cell.index
                        onOpenRequested: {
                            noteGrid.currentIndex = cell.index
                            window.noteAction(cell.modelData.id, "open")
                        }
                        onActionRequested: function(action) { window.noteAction(cell.modelData.id, action) }
                    }
                }
            }
        }
    }

    // Edge and corner handles for the frameless window.
    component ResizeEdge: MouseArea {
        property int edges: 0
        z: 100
        enabled: !window.maximized
        acceptedButtons: Qt.LeftButton
        onPressed: window.startSystemResize(edges)
    }
    ResizeEdge { edges: Qt.LeftEdge; cursorShape: Qt.SizeHorCursor; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 12 } width: 5; anchors.leftMargin: 0 }
    ResizeEdge { edges: Qt.RightEdge; cursorShape: Qt.SizeHorCursor; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 12 } width: 5; anchors.rightMargin: 0 }
    ResizeEdge { edges: Qt.TopEdge; cursorShape: Qt.SizeVerCursor; anchors { top: parent.top; left: parent.left; right: parent.right; margins: 12 } height: 5; anchors.topMargin: 0 }
    ResizeEdge { edges: Qt.BottomEdge; cursorShape: Qt.SizeVerCursor; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 12 } height: 5; anchors.bottomMargin: 0 }
    ResizeEdge { edges: Qt.TopEdge | Qt.LeftEdge; cursorShape: Qt.SizeFDiagCursor; anchors { top: parent.top; left: parent.left } width: 12; height: 12 }
    ResizeEdge { edges: Qt.TopEdge | Qt.RightEdge; cursorShape: Qt.SizeBDiagCursor; anchors { top: parent.top; right: parent.right } width: 12; height: 12 }
    ResizeEdge { edges: Qt.BottomEdge | Qt.LeftEdge; cursorShape: Qt.SizeBDiagCursor; anchors { bottom: parent.bottom; left: parent.left } width: 12; height: 12 }
    ResizeEdge { edges: Qt.BottomEdge | Qt.RightEdge; cursorShape: Qt.SizeFDiagCursor; anchors { bottom: parent.bottom; right: parent.right } width: 12; height: 12 }

    // Short confirmation for actions with no other visible effect.
    Rectangle {
        id: toast
        property alias text: toastLabel.text
        property bool shown: false
        z: 200
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: shown ? 24 : 8
        opacity: shown ? 1 : 0
        visible: opacity > 0
        implicitWidth: toastLabel.implicitWidth + 32
        implicitHeight: 36
        radius: 18
        color: theme.textPrimary
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150 } }
        Label {
            id: toastLabel
            anchors.centerIn: parent
            font.pixelSize: 12
            color: theme.windowBackground
        }
        Timer { id: toastTimer; interval: 1800; onTriggered: toast.shown = false }
    }

    Dialog {
        id: deleteDialog
        property string noteId: ""
        readonly property string noteTitle: {
            const i = backend.noteIds.indexOf(noteId)
            return i >= 0 && backend.titles[i].trim().length ? backend.titles[i] : qsTr("Untitled note")
        }
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(400, window.width - 48)
        modal: true
        title: qsTr("Delete “%1”?").arg(noteTitle)
        standardButtons: Dialog.Cancel | Dialog.Ok
        Label {
            width: parent.width
            text: qsTr("The note and its unsaved changes will be deleted. This cannot be undone. Use Archive to put a note away instead.")
            wrapMode: Text.WordWrap
        }
        Component.onCompleted: {
            const ok = standardButton(Dialog.Ok)
            if (ok) ok.text = qsTr("Delete")
        }
        onAccepted: window.deleteNoteConfirmed(noteId)
    }

    // One labelled switch in the settings popup.
    component SettingRow: RowLayout {
        id: row
        property string title: ""
        property string detail: ""
        property alias checked: toggle.checked
        signal toggled(bool checked)
        spacing: 12
        Layout.fillWidth: true

        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Label {
                text: row.title
                font.pixelSize: 13
                font.weight: Font.Medium
                color: row.enabled ? theme.textPrimary : theme.textMuted
                Layout.fillWidth: true
            }
            Label {
                text: row.detail
                visible: text.length > 0
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                color: theme.textSecondary
                Layout.fillWidth: true
            }
        }
        Switch {
            id: toggle
            Accessible.name: row.title
            Layout.alignment: Qt.AlignVCenter
            onToggled: row.toggled(checked)
        }
    }

    Popup {
        id: settingsPopup
        parent: Overlay.overlay
        x: Math.round((window.width - width) / 2)
        y: 72
        width: Math.min(460, window.width - 32)
        padding: 20
        modal: true
        focus: true
        background: Rectangle {
            radius: theme.radiusLg
            color: theme.surface
            border.width: 1
            border.color: theme.border
        }

        readonly property bool layersSupported: applicationInfo.supportsNoteLayers()

        contentItem: ColumnLayout {
            spacing: 18

            Label {
                text: qsTr("Settings")
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: theme.textPrimary
            }

            ColumnLayout {
                spacing: 8
                Layout.fillWidth: true
                Label {
                    text: qsTr("Appearance")
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: theme.textPrimary
                }
                RowLayout {
                    spacing: 6
                    Repeater {
                        model: [
                            {mode: "system", label: qsTr("System"), icon: "monitor"},
                            {mode: "light", label: qsTr("Light"), icon: "sun"},
                            {mode: "dark", label: qsTr("Dark"), icon: "moon"}
                        ]
                        delegate: UI.StyledButton {
                            required property var modelData
                            text: modelData.label
                            iconName: modelData.icon
                            iconSize: 14
                            theme: window.theme
                            variant: backend.themeMode === modelData.mode ? "accent" : "secondary"
                            implicitHeight: 32
                            onClicked: backend.setThemeMode(modelData.mode)
                        }
                    }
                }
            }

            SettingRow {
                id: stayBelowRow
                title: qsTr("Keep notes on the desktop")
                detail: settingsPopup.layersSupported
                    ? qsTr("Unpinned notes stay beneath other windows. Pinned notes always stay on top.")
                    : qsTr("Not available on this desktop: on Wayland only KDE Plasma lets notes stay beneath other windows.")
                enabled: settingsPopup.layersSupported && backend.ready
                checked: backend.notesStayBelow
                onToggled: function(checked) {
                    if (!backend.setNotesStayBelow(checked)) stayBelowRow.checked = backend.notesStayBelow
                }
            }

            SettingRow {
                id: autostartRow
                title: qsTr("Start at login")
                detail: qsTr("Open BetterNotes in the background when you sign in.")
                checked: backend.autostartEnabled
                onToggled: function(checked) {
                    if (!backend.setAutostart(checked)) autostartRow.checked = backend.autostartEnabled
                }
            }

            SettingRow {
                id: installRow
                readonly property bool available: applicationInfo.canInstall()
                title: qsTr("Show in applications menu")
                detail: available
                    ? qsTr("Install BetterNotes for your user with its icon, so it can be launched from the menu and pinned to the taskbar. No administrator rights needed; removing it keeps your notes.")
                    : qsTr("Already installed by your package manager or Flatpak.")
                enabled: available
                checked: !available || applicationInfo.isInstalled()
                onToggled: function(checked) {
                    const error = applicationInfo.setInstalled(checked)
                    installRow.checked = applicationInfo.isInstalled()
                    if (error.length > 0) window.showToast(error)
                    else window.showToast(checked ? qsTr("Added to the applications menu") : qsTr("Removed from the applications menu"))
                }
            }
        }
    }

    UI.ReminderEditor {
        id: reminderEditor
        objectName: "libraryReminderEditor"
        property string noteId: ""
        theme: window.theme
        onSaveRequested: function(seconds, recurrence) {
            if (backend.setNoteReminder(noteId, seconds, recurrence)) {
                window.reminderChanged(noteId)
                window.showToast(qsTr("Reminder set"))
            }
        }
        onRemoveRequested: {
            if (backend.clearNoteReminder(noteId)) {
                window.reminderChanged(noteId)
                window.showToast(qsTr("Reminder removed"))
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
        // The bundled icon, the same one the windows use. A theme icon name
        // would show nothing where the theme lacks it.
        icon.source: "qrc:/betternotes/icons/app-64.png"
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
    Shortcut { sequences: [StandardKey.Find]; context: Qt.WindowShortcut; onActivated: searchField.forceActiveFocus() }
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
