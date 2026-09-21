pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
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
    property alias deleteForeverDialog: deleteDialog
    property alias settingsPopupItem: settingsPopup
    property alias keySequencesItem: keySequences
    property var noteWindows: ({})
    property string windowError: ""
    property string filterTab: "all"
    property string tagFilter: ""
    // noteWindows is a plain object, so bindings cannot see it change. Anything
    // that shows which notes are open also reads this counter.
    property int windowsRevision: 0
    property string searchFilter: ""
    // Multi-selection in the library: selected note ids, and the card a
    // Shift+click range starts from. selectionRevision makes bindings see
    // changes to the plain object.
    property var selectedIds: ({})
    property int selectionRevision: 0
    property string selectionAnchor: ""
    readonly property int selectionCount: selectionRevision >= 0 ? Object.keys(selectedIds).length : 0
    property var quickCaptureWindow: null

    Themes.Theme { id: theme; themeMode: backend.themeMode; accentColor: backend.accentColor }
    KeySequences { id: keySequences }
    // Configurable shortcuts {action: sequence}, shared with the note windows.
    readonly property var keys: {
        try {
            return JSON.parse(backend.shortcutsJson || "{}")
        } catch (error) {
            return {}
        }
    }
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
            appearanceMode: backend.themeMode
            appearanceAccent: backend.accentColor
            keys: window.keys
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
        backend.runAutoBackup()
        backend.setReminderTexts(qsTr("Reminder from BetterNotes"), qsTr("Open note"), qsTr("Snooze 10 min"))
        const ids = backend.restoreIds
        const errors = []
        for (let i = 0; i < ids.length; ++i) {
            if (!openNote(ids[i])) errors.push(windowError)
        }
        windowError = errors.join("\n")
        if (applicationInfo.startQuickCapture()) {
            openQuickCapture()
        }
        const files = applicationInfo.startFiles()
        if (files.length > 0) openNotesFrom(backend.openFiles(files))
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

    // Opens the notes made from files ("Open with BetterNotes").
    function openNotesFrom(ids) {
        for (let i = 0; i < ids.length; ++i) openNote(ids[i])
        if (backend.errorMessage.length > 0) showToast(backend.errorMessage)
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

    // Lays the open notes out in rows on the library's screen, largest gaps
    // closed, so notes scattered or lost on the desktop are easy to reach.
    // X11 lets the app place windows itself; on KDE Plasma under Wayland the
    // desktop integration moves them; other Wayland desktops allow neither,
    // so the notes are only brought on screen there.
    function arrangeNotes() {
        const ids = Object.keys(noteWindows).sort(function(a, b) { return Number(a) - Number(b) })
        // Only the notes already open; closed notes stay closed.
        for (const id of ids) {
            const sticky = noteWindows[id]
            if (sticky.visibility === Window.Minimized) sticky.showNormal()
            else if (!sticky.visible) sticky.show()
        }
        if (ids.length === 0) return "none"
        const direct = applicationInfo.canPositionWindows(Qt.platform.pluginName)
        const viaDesktop = !direct && placementService.available && applicationInfo.supportsNoteLayers()
        if (!direct && !viaDesktop) return "unsupported"
        const area = window.screen
        const margin = 24
        const left = area.virtualX + margin
        const right = area.virtualX + area.width - margin
        let x = left
        let y = area.virtualY + 64
        let rowHeight = 0
        for (const id of ids) {
            const sticky = noteWindows[id]
            const width = sticky.width
            const height = sticky.height
            if (x > left && x + width > right) {
                x = left
                y += rowHeight + margin
                rowHeight = 0
            }
            if (direct) {
                sticky.x = x
                sticky.y = y
            } else {
                placementService.track(id, true, x, y)
                sticky.moveReported(x, y)
                sticky.arrangeMarker = !sticky.arrangeMarker
            }
            x += width + margin
            rowHeight = Math.max(rowHeight, height)
        }
        return "arranged"
    }

    function arrangeNotesWithFeedback() {
        const result = arrangeNotes()
        if (result === "unsupported") showToast(qsTr("This desktop does not let apps arrange windows; the open notes were brought on screen instead."))
        else if (result === "none") showToast(qsTr("No notes are open on the desktop."))
        else showToast(qsTr("Notes arranged"))
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
                reminder: known ? (backend.noteReminders[i] || "") : "",
                trashed: false,
                deletedAt: 0
            }
        }
        if (filterTab === "trash" && searchFilter.length === 0) {
            for (let t = 0; t < backend.trashIds.length; ++t) {
                rows.push({
                    id: backend.trashIds[t], title: backend.trashTitles[t], snippet: backend.trashSnippets[t] || "",
                    tags: [], pinned: false, archived: false, priority: 0, tint: "yellow", reminder: "",
                    trashed: true, deletedAt: parseFloat(backend.trashDeletedAt[t] || "0")
                })
            }
            return rows
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
        if (filterTab === "trash") return qsTr("Trash")
        return qsTr("All notes")
    }

    function showSection(tab, tag) {
        clearSelection()
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
            // Opening a result is what makes a search worth remembering.
            if (searchFilter.length > 0) backend.rememberSearch(searchFilter)
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
            // The trash keeps it for 30 days, so this needs no confirmation.
            if (sticky) sticky.deleteConfirmed()
            else backend.deleteNoteById(id)
            showToast(qsTr("Moved to the trash"))
        } else if (action === "restore-trash") {
            if (backend.restoreNote(id)) showToast(qsTr("Restored"))
        } else if (action === "delete-forever") {
            deleteDialog.noteIds = [id]
            deleteDialog.open()
        }
    }

    // ---- Selection ----------------------------------------------------------

    function toggleSelected(id, range) {
        const ids = visibleNotes.map(function(note) { return note.id })
        if (range && selectionAnchor.length && ids.indexOf(selectionAnchor) >= 0) {
            const from = ids.indexOf(selectionAnchor)
            const to = ids.indexOf(id)
            for (let i = Math.min(from, to); i <= Math.max(from, to); ++i) selectedIds[ids[i]] = true
        } else if (selectedIds[id]) {
            delete selectedIds[id]
        } else {
            selectedIds[id] = true
        }
        selectionAnchor = id
        selectionRevision += 1
    }

    function selectAllVisible() {
        for (const note of visibleNotes) selectedIds[note.id] = true
        selectionRevision += 1
    }

    function clearSelection() {
        selectedIds = ({})
        selectionAnchor = ""
        selectionRevision += 1
    }

    // Runs a card action on every selected note, then clears the selection.
    function bulkAction(action) {
        const ids = Object.keys(selectedIds)
        clearSelection()
        if (action === "delete-forever") {
            deleteDialog.noteIds = ids
            deleteDialog.open()
            return
        }
        for (const id of ids) {
            const sticky = noteWindows[id]
            if (action === "delete") {
                if (sticky) sticky.deleteConfirmed()
                else backend.deleteNoteById(id)
            } else if (action === "restore-trash") {
                backend.restoreNote(id)
            } else {
                noteAction(id, action)
            }
        }
        if (action === "delete") showToast(qsTr("Moved %n note(s) to the trash", "", ids.length))
    }

    function bulkTag(tag) {
        const ids = Object.keys(selectedIds)
        for (const id of ids) {
            const sticky = noteWindows[id]
            if (sticky) {
                sticky.addTags(tag)
                sticky.flush()
            } else {
                backend.addNoteTag(id, tag)
            }
        }
        clearSelection()
        showToast(qsTr("Tagged %n note(s)", "", ids.length))
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

    function deleteForeverConfirmed(ids) {
        for (const id of ids) backend.deleteForever(id)
        showToast(qsTr("Deleted %n note(s) for good", "", ids.length))
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
                SidebarItem {
                    objectName: "trashSection"
                    text: qsTr("Trash")
                    iconName: "trash"
                    count: backend.trashIds.length
                    selected: window.searchFilter.length === 0 && window.filterTab === "trash"
                    onClicked: window.showSection("trash")
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
                    objectName: "arrangeNotesItem"
                    text: qsTr("Arrange notes")
                    iconName: "layout-grid"
                    enabled: window.windowsRevision >= 0 && Object.keys(window.noteWindows).length > 0
                    onClicked: window.arrangeNotesWithFeedback()
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
                        placeholderText: qsTr("Search all notes: titles, text and tags")
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
                        onAccepted: if (window.searchFilter.length > 0) backend.rememberSearch(window.searchFilter)
                        onActiveFocusChanged: if (activeFocus && text.length === 0) recentSearches.refresh()

                        // Recent searches, offered while the field is empty.
                        Popup {
                            id: recentSearches
                            objectName: "recentSearches"
                            property var items: []
                            function refresh() {
                                items = backend.recentSearches()
                                if (items.length > 0) open()
                            }
                            y: searchField.height + 4
                            width: searchField.width
                            padding: 4
                            visible: false
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                            background: Rectangle {
                                radius: 10
                                color: theme.surface
                                border.width: 1
                                border.color: theme.border
                            }
                            Connections {
                                target: searchField
                                function onTextChanged() { if (searchField.text.length > 0) recentSearches.close() }
                            }
                            contentItem: ColumnLayout {
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 8
                                    Label {
                                        text: qsTr("Recent searches")
                                        font.pixelSize: 11
                                        color: theme.textMuted
                                        Layout.fillWidth: true
                                    }
                                    UI.StyledButton {
                                        text: qsTr("Clear")
                                        theme: window.theme
                                        variant: "ghost"
                                        font.pixelSize: 11
                                        implicitHeight: 24
                                        focusPolicy: Qt.NoFocus
                                        onClicked: {
                                            backend.clearRecentSearches()
                                            recentSearches.close()
                                        }
                                    }
                                }
                                Repeater {
                                    model: recentSearches.items
                                    delegate: ItemDelegate {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        focusPolicy: Qt.NoFocus
                                        contentItem: RowLayout {
                                            spacing: 8
                                            UI.AppIcon { name: "clock"; size: 13; color: theme.textMuted }
                                            Label {
                                                text: parent.parent.modelData
                                                textFormat: Text.PlainText
                                                elide: Text.ElideRight
                                                color: theme.textPrimary
                                                font.pixelSize: 13
                                                Layout.fillWidth: true
                                            }
                                        }
                                        background: Rectangle {
                                            radius: 6
                                            color: parent.hovered ? theme.surfaceHover : "transparent"
                                        }
                                        onClicked: {
                                            recentSearches.close()
                                            searchField.text = modelData
                                        }
                                    }
                                }
                            }
                        }

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
                visible: backend.ready && window.selectionCount === 0

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
                UI.StyledButton {
                    objectName: "emptyTrashButton"
                    visible: window.filterTab === "trash" && window.searchFilter.length === 0 && backend.trashIds.length > 0
                    theme: window.theme
                    variant: "danger"
                    text: qsTr("Empty Trash")
                    onClicked: emptyTrashDialog.open()
                }
            }

            Label {
                visible: backend.ready && window.filterTab === "trash" && window.searchFilter.length === 0 && window.selectionCount === 0
                text: qsTr("Deleted notes stay here for 30 days, then they are deleted for good.")
                font.pixelSize: 12
                color: theme.textSecondary
                Layout.leftMargin: 24
                Layout.bottomMargin: 10
            }

            // Actions for the selected notes, in place of the heading.
            RowLayout {
                objectName: "selectionBar"
                visible: backend.ready && window.selectionCount > 0
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.bottomMargin: 12
                spacing: 6
                readonly property bool inTrash: window.filterTab === "trash" && window.searchFilter.length === 0

                UI.StyledButton {
                    iconName: "x"
                    theme: window.theme
                    variant: "ghost"
                    implicitWidth: 30
                    implicitHeight: 30
                    padding: 0
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Clear selection (Esc)")
                    onClicked: window.clearSelection()
                }
                Label {
                    text: qsTr("%n selected", "", window.selectionCount)
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: theme.textPrimary
                    Layout.fillWidth: true
                }
                UI.StyledButton {
                    theme: window.theme
                    variant: "ghost"
                    text: qsTr("Select All")
                    onClicked: window.selectAllVisible()
                }
                UI.StyledButton {
                    visible: !parent.inTrash
                    theme: window.theme
                    iconName: "pin"
                    text: qsTr("Pin")
                    onClicked: window.bulkAction("pin")
                }
                UI.StyledButton {
                    visible: !parent.inTrash
                    theme: window.theme
                    iconName: window.filterTab === "archived" ? "archive-restore" : "archive"
                    text: window.filterTab === "archived" ? qsTr("Unarchive") : qsTr("Archive")
                    onClicked: window.bulkAction(window.filterTab === "archived" ? "restore" : "archive")
                }
                UI.StyledButton {
                    visible: !parent.inTrash
                    theme: window.theme
                    iconName: "tag"
                    text: qsTr("Tag…")
                    onClicked: bulkTagDialog.open()
                }
                UI.StyledButton {
                    visible: !parent.inTrash
                    objectName: "bulkTrashButton"
                    theme: window.theme
                    variant: "danger"
                    iconName: "trash"
                    text: qsTr("Move to Trash")
                    onClicked: window.bulkAction("delete")
                }
                UI.StyledButton {
                    visible: parent.inTrash
                    theme: window.theme
                    iconName: "archive-restore"
                    text: qsTr("Restore")
                    onClicked: window.bulkAction("restore-trash")
                }
                UI.StyledButton {
                    visible: parent.inTrash
                    theme: window.theme
                    variant: "danger"
                    iconName: "trash"
                    text: qsTr("Delete for Good")
                    onClicked: window.bulkAction("delete-forever")
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
                Keys.onDeletePressed: {
                    if (window.selectionCount > 0) {
                        window.bulkAction(window.filterTab === "trash" ? "delete-forever" : "delete")
                    } else if (currentIndex >= 0) {
                        const note = window.visibleNotes[currentIndex]
                        window.noteAction(note.id, note.trashed ? "delete-forever" : "delete")
                    }
                }
                Keys.onEscapePressed: function(event) {
                    event.accepted = window.selectionCount > 0
                    window.clearSelection()
                }
                Keys.onPressed: function(event) {
                    if (event.matches(StandardKey.SelectAll)) {
                        window.selectAllVisible()
                        event.accepted = true
                    }
                }
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
                        trashed: cell.modelData.trashed
                        deletedAt: cell.modelData.deletedAt
                        selected: window.selectionRevision >= 0 && !!window.selectedIds[cell.modelData.id]
                        selecting: window.selectionCount > 0
                        onSelectRequested: function(range) {
                            noteGrid.currentIndex = cell.index
                            window.toggleSelected(cell.modelData.id, range)
                        }
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
        objectName: "deleteForeverDialog"
        property var noteIds: []
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(400, window.width - 48)
        modal: true
        title: qsTr("Delete %n note(s) for good?", "", noteIds.length)
        standardButtons: Dialog.Cancel | Dialog.Ok
        Label {
            width: parent.width
            text: qsTr("They and their attached files will be deleted. This cannot be undone.")
            wrapMode: Text.WordWrap
        }
        Component.onCompleted: {
            const ok = standardButton(Dialog.Ok)
            if (ok) ok.text = qsTr("Delete for Good")
        }
        onAccepted: window.deleteForeverConfirmed(noteIds)
    }

    Dialog {
        id: emptyTrashDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(400, window.width - 48)
        modal: true
        title: qsTr("Empty the trash?")
        standardButtons: Dialog.Cancel | Dialog.Ok
        Label {
            width: parent.width
            text: qsTr("All %n note(s) in the trash and their attached files will be deleted. This cannot be undone.", "", backend.trashIds.length)
            wrapMode: Text.WordWrap
        }
        Component.onCompleted: {
            const ok = standardButton(Dialog.Ok)
            if (ok) ok.text = qsTr("Empty Trash")
        }
        onAccepted: {
            const count = backend.emptyTrash()
            if (count >= 0) window.showToast(qsTr("Deleted %n note(s) for good", "", count))
        }
    }

    Dialog {
        id: bulkTagDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(360, window.width - 48)
        modal: true
        title: qsTr("Add a tag to %n note(s)", "", window.selectionCount)
        standardButtons: Dialog.Cancel | Dialog.Ok
        onOpened: { bulkTagField.text = ""; bulkTagField.forceActiveFocus() }
        UI.StyledTextField {
            id: bulkTagField
            width: parent.width
            theme: window.theme
            placeholderText: qsTr("Tag name")
            onAccepted: bulkTagDialog.accept()
        }
        onAccepted: if (bulkTagField.text.trim().length) window.bulkTag(bulkTagField.text)
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
        onOpened: backupSection.refresh()

        // Scrolls once the settings are taller than the window.
        contentItem: ScrollView {
            id: settingsScroll
            objectName: "librarySettingsScroll"
            contentWidth: availableWidth
            clip: true
            implicitHeight: Math.min(settingsColumn.implicitHeight, window.height - 120)
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: settingsColumn
            width: settingsScroll.availableWidth
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
                Flow {
                    spacing: 6
                    Layout.fillWidth: true
                    Repeater {
                        model: [
                            {mode: "system", label: qsTr("System"), icon: "monitor"},
                            {mode: "light", label: qsTr("Light"), icon: "sun"},
                            {mode: "dark", label: qsTr("Dark"), icon: "moon"},
                            {mode: "sepia", label: qsTr("Sepia"), icon: "palette"},
                            {mode: "black", label: qsTr("Black"), icon: "moon"}
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

                // Accent colour: buttons, selections and highlights.
                Label {
                    text: qsTr("Accent colour")
                    font.pixelSize: 12
                    color: theme.textSecondary
                    Layout.topMargin: 4
                }
                Flow {
                    objectName: "accentSwatches"
                    spacing: 8
                    Layout.fillWidth: true
                    Repeater {
                        model: ["#6366f1", "#3b82f6", "#0ea5e9", "#14b8a6", "#22c55e", "#f59e0b", "#f97316", "#ef4444", "#ec4899", "#a855f7", "#64748b"]
                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool chosen: backend.accentColor === modelData
                            width: 26
                            height: 26
                            radius: 13
                            color: modelData
                            border.width: chosen ? 3 : 1
                            border.color: chosen ? theme.textPrimary : Qt.darker(modelData, 1.2)
                            UI.AppIcon {
                                anchors.centerIn: parent
                                visible: parent.chosen
                                name: "check"
                                size: 13
                                strokeWidth: 3
                                color: "white"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: backend.setAccentColor(parent.modelData)
                            }
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

            // ---- Backups ----------------------------------------------------
            ColumnLayout {
                id: backupSection
                objectName: "backupSection"
                spacing: 10
                Layout.fillWidth: true
                property var settings: ({})

                function refresh() {
                    try {
                        settings = JSON.parse(backend.autoBackupSettings() || "{}")
                    } catch (error) {
                        settings = {}
                    }
                }

                function apply(changes) {
                    const next = Object.assign({}, settings, changes)
                    if (!backend.setAutoBackupSettings(next.enabled, next.interval, next.keep, next.folder))
                        window.showToast(backend.errorMessage)
                    refresh()
                }

                Label {
                    text: qsTr("Backups")
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: theme.textPrimary
                }

                SettingRow {
                    id: autoBackupRow
                    title: qsTr("Back up automatically")
                    detail: backupSection.settings.last > 0
                        ? qsTr("Last backup: %1").arg(new Date(backupSection.settings.last * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat))
                        : qsTr("No backup yet. Backups copy your notes and attached files.")
                    checked: backupSection.settings.enabled === true
                    onToggled: function(checked) { backupSection.apply({ enabled: checked }) }
                }

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    enabled: backupSection.settings.enabled === true
                    ComboBox {
                        objectName: "backupInterval"
                        textRole: "text"
                        valueRole: "value"
                        model: [
                            { value: "daily", text: qsTr("Every day") },
                            { value: "weekly", text: qsTr("Every week") }
                        ]
                        currentIndex: backupSection.settings.interval === "weekly" ? 1 : 0
                        onActivated: backupSection.apply({ interval: currentValue })
                        Layout.fillWidth: true
                    }
                    Label {
                        text: qsTr("Keep")
                        color: theme.textSecondary
                        font.pixelSize: 12
                    }
                    SpinBox {
                        objectName: "backupKeep"
                        from: 1
                        to: 100
                        value: backupSection.settings.keep || 7
                        editable: true
                        onValueModified: backupSection.apply({ keep: value })
                    }
                }

                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Label {
                        text: backupSection.settings.target || ""
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        font.pixelSize: 11
                        color: theme.textSecondary
                        Layout.fillWidth: true
                    }
                    UI.StyledButton {
                        theme: window.theme
                        variant: "ghost"
                        text: qsTr("Change Folder…")
                        onClicked: backupFolderDialog.open()
                    }
                    UI.StyledButton {
                        theme: window.theme
                        variant: "ghost"
                        visible: (backupSection.settings.folder || "").length > 0
                        text: qsTr("Default")
                        onClicked: backupSection.apply({ folder: "" })
                    }
                }

                RowLayout {
                    spacing: 8
                    UI.StyledButton {
                        objectName: "backupNowButton"
                        theme: window.theme
                        text: qsTr("Back Up Now")
                        onClicked: {
                            const made = backend.backupNow()
                            backupSection.refresh()
                            window.showToast(made.length > 0 ? qsTr("Backed up") : qsTr("Backup failed: %1").arg(backend.errorMessage))
                        }
                    }
                    UI.StyledButton {
                        theme: window.theme
                        variant: "ghost"
                        text: qsTr("Open Folder")
                        onClicked: Qt.openUrlExternally("file://" + backupSection.settings.target)
                    }
                }
                Label {
                    text: qsTr("To restore, quit BetterNotes and run: betternotes restore <backup folder>")
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: theme.textMuted
                    Layout.fillWidth: true
                }

                FolderDialog {
                    id: backupFolderDialog
                    title: qsTr("Choose a Backup Folder")
                    onAccepted: backupSection.apply({ folder: selectedFolder.toString() })
                }
            }

            // ---- Keyboard shortcuts ------------------------------------------
            ColumnLayout {
                id: shortcutSection
                objectName: "shortcutSection"
                spacing: 4
                Layout.fillWidth: true
                // The action being recorded, or "".
                property string recording: ""

                readonly property var labels: ({
                    new_note: qsTr("New note"),
                    focus_search: qsTr("Search the library"),
                    command_palette: qsTr("Command palette"),
                    quick_capture: qsTr("Quick Capture (while BetterNotes is active)"),
                    bold: qsTr("Bold"),
                    italic: qsTr("Italic"),
                    underline: qsTr("Underline"),
                    heading1: qsTr("Heading 1"),
                    heading2: qsTr("Heading 2"),
                    bullet_list: qsTr("Bulleted list"),
                    numbered_list: qsTr("Numbered list"),
                    checklist: qsTr("Checklist"),
                    toggle_check: qsTr("Tick checklist item"),
                    find: qsTr("Find in note"),
                    replace: qsTr("Replace in note"),
                    align_left: qsTr("Align left"),
                    align_center: qsTr("Align center"),
                    align_right: qsTr("Align right"),
                    align_justify: qsTr("Justify")
                })
                readonly property var libraryActions: ["new_note", "focus_search", "command_palette", "quick_capture"]

                function record(action, event) {
                    if (event.key === Qt.Key_Escape) {
                        recording = ""
                        event.accepted = true
                        return
                    }
                    const sequence = keySequences.fromKey(event.key, event.modifiers)
                    event.accepted = true
                    if (sequence.length === 0) return
                    recording = ""
                    const refused = backend.setShortcut(action, sequence)
                    if (refused.length > 0) window.showToast(refused)
                }

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: qsTr("Keyboard shortcuts")
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: theme.textPrimary
                        Layout.fillWidth: true
                    }
                    UI.StyledButton {
                        theme: window.theme
                        variant: "ghost"
                        text: qsTr("Reset All")
                        onClicked: backend.resetShortcuts()
                    }
                }
                Label {
                    text: qsTr("Click a shortcut, then press the new keys. Esc cancels.")
                    font.pixelSize: 11
                    color: theme.textMuted
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: Object.keys(shortcutSection.labels)
                    delegate: RowLayout {
                        id: shortcutRow
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        Label {
                            visible: shortcutRow.modelData === "new_note" || shortcutRow.modelData === "bold"
                            text: shortcutRow.modelData === "new_note" ? qsTr("Library") : qsTr("Notes")
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: theme.textSecondary
                            Layout.topMargin: 6
                            Layout.preferredWidth: 60
                        }
                        Item { visible: shortcutRow.modelData !== "new_note" && shortcutRow.modelData !== "bold"; Layout.preferredWidth: 60 }
                        Label {
                            text: shortcutSection.labels[shortcutRow.modelData]
                            font.pixelSize: 12
                            color: theme.textPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        UI.StyledButton {
                            id: recorder
                            objectName: "shortcut_" + shortcutRow.modelData
                            readonly property bool active: shortcutSection.recording === shortcutRow.modelData
                            theme: window.theme
                            variant: active ? "accent" : "secondary"
                            implicitHeight: 28
                            Layout.preferredWidth: 150
                            text: active ? qsTr("Press keys…") : keySequences.display(window.keys[shortcutRow.modelData] || "")
                            onClicked: {
                                shortcutSection.recording = shortcutRow.modelData
                                forceActiveFocus()
                            }
                            onActiveFocusChanged: if (!activeFocus && active) shortcutSection.recording = ""
                            Keys.onPressed: function(event) {
                                if (active) shortcutSection.record(shortcutRow.modelData, event)
                            }
                        }
                    }
                }
            }
        }
        }
    }

    // ---- Export and import --------------------------------------------------

    function fileName(url) {
        return decodeURIComponent(url.toString().replace(/^.*\//, ""))
    }

    FileDialog {
        id: exportJsonDialog
        title: qsTr("Export Notes")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [qsTr("JSON files (*.json)")]
        currentFolder: backend.documentsFolder()
        selectedFile: currentFolder + "/betternotes-notes.json"
        onAccepted: {
            if (backend.exportNotesJson(selectedFile.toString())) {
                window.showToast(qsTr("Notes exported to %1").arg(window.fileName(selectedFile)))
            } else {
                window.showToast(qsTr("Export failed: %1").arg(backend.errorMessage))
            }
        }
    }

    FolderDialog {
        id: exportMarkdownDialog
        title: qsTr("Export Notes as Markdown — choose a folder")
        onAccepted: {
            if (backend.exportNotesMarkdown(selectedFolder.toString())) {
                window.showToast(qsTr("Notes exported to %1").arg(window.fileName(selectedFolder)))
            } else {
                window.showToast(qsTr("Export failed: %1").arg(backend.errorMessage))
            }
        }
    }

    FileDialog {
        id: importDialog
        title: qsTr("Import Notes")
        fileMode: FileDialog.OpenFiles
        nameFilters: [qsTr("BetterNotes exports and Markdown (*.json *.md *.markdown *.txt)")]
        onAccepted: {
            let imported = 0
            const failed = []
            for (let i = 0; i < selectedFiles.length; ++i) {
                const url = selectedFiles[i].toString()
                const count = /\.json$/i.test(url) ? backend.importNotesJson(url) : backend.importNoteMarkdown(url)
                if (count < 0) failed.push(window.fileName(url) + ": " + backend.errorMessage)
                else imported += count
            }
            backend.reload()
            if (failed.length > 0) window.showToast(qsTr("Imported %1 notes; could not import %2").arg(imported).arg(failed.join("; ")))
            else window.showToast(qsTr("Imported %1 notes").arg(imported))
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
            else if (action === "arrange") window.arrangeNotesWithFeedback()
            else if (action === "hide_all") window.hideAllNotes()
            else if (action === "toggle_theme") {
                if (backend.themeMode === "system") backend.setThemeMode("light")
                else if (backend.themeMode === "light") backend.setThemeMode("dark")
                else backend.setThemeMode("system")
            }
            else if (action === "diagnostics") diagnosticsDialog.open()
            else if (action === "export_json") exportJsonDialog.open()
            else if (action === "export_markdown") exportMarkdownDialog.open()
            else if (action === "import") importDialog.open()
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
                text: qsTr("Arrange notes")
                onTriggered: window.arrangeNotesWithFeedback()
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
                text: qsTr("Export notes…")
                onTriggered: {
                    window.showNormal()
                    window.requestActivate()
                    exportJsonDialog.open()
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

    Shortcut { sequence: window.keys.new_note || "Ctrl+N"; context: Qt.WindowShortcut; enabled: backend.ready; onActivated: window.createNote() }
    Shortcut { sequences: [StandardKey.Quit]; context: Qt.WindowShortcut; onActivated: window.close() }
    Shortcut { sequences: [window.keys.command_palette || "Ctrl+K", "Ctrl+Shift+P"]; context: Qt.WindowShortcut; onActivated: commandPalette.open() }
    Shortcut { sequence: window.keys.focus_search || "Ctrl+F"; context: Qt.WindowShortcut; onActivated: searchField.forceActiveFocus() }
    Shortcut { sequence: window.keys.quick_capture || "Ctrl+Alt+Space"; onActivated: window.openQuickCapture() }

    // Automatic backups are due daily at most; checking hourly is plenty.
    Timer {
        interval: 60 * 60 * 1000
        running: backend.ready
        repeat: true
        onTriggered: backend.runAutoBackup()
    }

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
                } else if (action.startsWith("opened:")) {
                    window.openNotesFrom(action.substring(7).split(",").filter(function(id) { return id.length > 0 }))
                } else if (action.startsWith("snoozed:")) {
                    window.reminderChanged(action.substring(8))
                    window.showToast(qsTr("Reminder snoozed for 10 minutes"))
                }
            }
        }
    }
}
