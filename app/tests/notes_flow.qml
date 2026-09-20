import QtQuick
import BetterNotes.App
import "qrc:/betternotes/windows" as UI
import "qrc:/betternotes/windows/WindowPlacement.js" as Placement

// Keeps Qt alive while the library and its windows are closed and reopened.
Window {
    id: harness
    visible: true
    width: 100
    height: 100
    property var library
    property var first
    property var second
    property string firstId
    property string secondId

    Component { id: mainWindow; UI.Main {} }
    NotesBackend { id: competingEditor }
    ApplicationInfo { id: platformInfo }

    function findItem(item, name) {
        if (item.objectName === name) return item
        if (item.children) {
            for (let i = 0; i < item.children.length; ++i) {
                const found = findItem(item.children[i], name)
                if (found) return found
            }
        }
        return null
    }
    function check(condition, message) {
        if (!condition) throw new Error(message)
    }
    function edit(window, title, content) {
        const titleInput = findItem(window.contentItem, "titleEditor")
        const body = findItem(window.contentItem, "contentEditor")
        check(titleInput && body, "Missing editor")
        titleInput.insert(0, title)
        titleInput.textEdited()
        body.insert(0, content)
    }
    function assertPlacementFallbacks() {
        const primary = {name: "primary", virtualX: 0, virtualY: 0, width: 1280, height: 720}
        const left = {name: "left", virtualX: -1280, virtualY: 0, width: 1280, height: 720}
        const saved = {screen: "left", x: -1200, y: 100, width: 420, height: 320, positioned: true}
        const retained = Placement.fit(saved, [primary, left], primary, false)
        check(retained.x === -1200 && retained.screen === left, "Negative monitor coordinates lost")
        const removed = Placement.fit(saved, [primary], primary, false)
        check(removed.x >= 0 && removed.y >= 40 && removed.screen === primary, "Disconnected monitor not recovered")
        const huge = Placement.fit({screen: "primary", x: 99999, y: -99999, width: 5000, height: 5000, positioned: true}, [primary], primary, false)
        check(huge.x >= 0 && huge.y >= 40 && huge.width < primary.width && huge.height < primary.height, "Offscreen/oversized geometry not clamped")
        check(!platformInfo.canPositionWindows("wayland") && !platformInfo.canPositionWindows("wayland-egl"), "Wayland must not restore absolute positions")
        check(!platformInfo.canPositionWindows("unknown"), "Unknown platforms must degrade safely")
        check(platformInfo.canPositionWindows("xcb"), "X11 placement unavailable")
    }

    Timer {
        interval: 10
        running: true
        onTriggered: {
            try {
                harness.assertPlacementFallbacks()
                harness.library = mainWindow.createObject(null)
                harness.check(harness.library && harness.library.libraryBackend.ready, "Library initialization failed")
                harness.check(harness.library.libraryBackend.themeMode === "system", "Default theme must be system")
                harness.check(harness.library.libraryBackend.setThemeMode("dark"), "Set dark theme failed")
                harness.check(harness.library.libraryBackend.themeMode === "dark", "Theme mode not dark")
                harness.check(harness.library.theme.isDark === true, "Theme isDark must be true in dark mode")
                harness.check(harness.library.libraryBackend.setThemeMode("light"), "Set light theme failed")
                harness.check(harness.library.theme.isDark === false, "Theme isDark must be false in light mode")
                harness.check(harness.library.libraryBackend.setThemeMode("system"), "Reset to system theme failed")
                harness.first = harness.library.createNote()
                harness.second = harness.library.createNote()
                harness.check(harness.first && harness.second && harness.first !== harness.second, "Independent windows missing")
                harness.firstId = harness.first.noteId
                harness.secondId = harness.second.noteId
                harness.check(harness.first.transientParent === null && harness.second.transientParent === null, "Notes are transient windows")
                harness.check(harness.library.openNote(harness.firstId) === harness.first, "Duplicate editor created")
                harness.edit(harness.first, "Autosaved title", "Plain <b>text</b>\nİstanbul 🦀")
                harness.edit(harness.second, "Second", "Independent draft")
                harness.first.width = 420
                harness.first.height = 320
                harness.first.x = 140
                harness.first.y = 120
                verifyAutosave.start()
            } catch (error) { console.error(error); Qt.exit(1) }
        }
    }
    Timer {
        id: verifyAutosave
        interval: 900
        onTriggered: {
            try {
                harness.check(!harness.first.editorBackend.dirty && !harness.second.editorBackend.dirty, "Independent autosave failed")
                harness.check(harness.first.editorBackend.draftContent === "Plain <b>text</b>\nİstanbul 🦀", "Markup interpreted or drafts crossed")
                harness.check(harness.first.editorBackend.savedWidth() === 420 && harness.first.editorBackend.savedHeight() === 320, "Debounced geometry save failed")
                // Simulate another connection changing the same note. Quitting must
                // retain all windows when any content save fails.
                harness.check(competingEditor.initializeNote(harness.firstId), "Competing editor failed")
                competingEditor.editTitle("Other process")
                harness.check(competingEditor.save(), "Competing save failed")
                harness.first.editorBackend.editContent("Keep this unsaved draft")
                harness.library.close()
                harness.check(harness.library.visible && Object.keys(harness.library.noteWindows).length === 2, "Failed quit lost windows")
                harness.check(harness.first.editorBackend.dirty && harness.first.editorBackend.draftContent === "Keep this unsaved draft", "Failed quit lost draft")
                harness.check(harness.first.editorBackend.reloadNote(), "Explicit reload failed")
                // Successful close saves immediately and retains the note in the list.
                const body = harness.findItem(harness.second.contentItem, "contentEditor")
                body.insert(body.length, "\nSaved on close")
                harness.second.close()
                harness.check(!harness.library.noteWindows[harness.secondId], "Closed window stayed registered")
                harness.check(harness.library.libraryBackend.titles.length === 2, "Close deleted the note")
                const disposable = harness.library.createNote()
                harness.check(disposable.deleteConfirmed(), "Confirmed delete failed")
                harness.check(harness.library.libraryBackend.titles.length === 2, "Delete failed to update library")
                harness.first.toggleCollapsed()
                harness.check(harness.first.collapsed && harness.first.height === harness.first.collapsedHeight, "Collapse failed")
                harness.check(harness.first.expandedHeight === 320, "Collapse lost expanded height")
                harness.first.close()
                harness.first = harness.library.openNote(harness.firstId)
                harness.check(harness.first.collapsed && harness.first.expandedHeight === 320, "Reopening lost collapse/size")
                harness.first.toggleCollapsed()
                harness.check(harness.first.height === 320, "Expand failed")
                const firstBody = harness.findItem(harness.first.contentItem, "contentEditor")
                firstBody.insert(firstBody.length, "\nSaved on quit")
                harness.library.close()
                harness.check(!harness.library.visible, "Successful quit rejected")
                harness.library.destroy()
                reopen.start()
            } catch (error) { console.error(error); Qt.exit(1) }
        }
    }
    Timer {
        id: reopen
        interval: 50
        onTriggered: {
            try {
                harness.library = mainWindow.createObject(null)
                harness.check(Object.keys(harness.library.noteWindows).length === 1, "Open/closed state not restored")
                harness.first = harness.library.noteWindows[harness.firstId]
                harness.check(harness.first && !harness.library.noteWindows[harness.secondId], "Wrong window restored")
                harness.check(harness.first.width === 420 && harness.first.height === 320, "Restored size mismatch")
                harness.check(harness.first.editorBackend.draftContent === "Plain <b>text</b>\nİstanbul 🦀\nSaved on quit", "Quit lost pending text")
                harness.first.toggleCollapsed()
                harness.library.close()
                harness.check(!harness.library.visible, "Final quit failed")
                Qt.exit(0)
            } catch (error) { console.error(error); Qt.exit(1) }
        }
    }
    Timer {
        interval: 10000
        running: true
        onTriggered: { console.error("QML test timed out"); Qt.exit(2) }
    }
}
