import QtQuick
import QtTest
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
    TestCase { id: input; name: "EditorInteraction"; when: false }

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

    // "Show all" reveals notes that are not on screen and must leave the ones
    // that already are exactly as they were. Stacking itself needs a real
    // compositor, so this covers the reveal contract the stacking bug broke:
    // every call used to show()/raise() windows that were already visible.
    function assertShowAllNotes(library, ids) {
        library.hideAllNotes()
        for (let i = 0; i < ids.length; ++i) {
            check(library.noteWindows[ids[i]].visibility === Window.Minimized, "Hide all left a note on screen")
        }
        library.showAllNotes()
        for (let i = 0; i < ids.length; ++i) {
            const sticky = library.noteWindows[ids[i]]
            check(sticky.visibility !== Window.Minimized, "Show all failed to restore a minimised note")
            check(sticky.visible, "Show all left a note hidden")
        }
        const before = ids.map(function(id) { return library.noteWindows[id].visibility })
        library.showAllNotes()
        check(Object.keys(library.noteWindows).length === ids.length, "Show all duplicated a note window")
        for (let i = 0; i < ids.length; ++i) {
            check(library.noteWindows[ids[i]].visibility === before[i], "Show all disturbed a note already on screen")
        }
    }

    function clickTool(window, name) {
        const button = findItem(window.contentItem, name)
        check(button && button.enabled, "Formatting button unavailable: " + name)
        input.mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton)
    }

    // Typed addresses become real, underlined links; typing after one does not
    // extend it; a click reaches the link handler. The clicked link is a file:
    // URL the core refuses, so the test never opens a browser.
    function assertLinks(window) {
        const body = findItem(window.contentItem, "contentEditor")
        body.forceActiveFocus()
        body.text = "Docs at https://example.com/guide. Thanks"
        window.linkifyContent()
        const start = window.plainContent.indexOf("https://")
        const end = start + "https://example.com/guide".length
        check(window.isRichText, "A note with an address did not switch to rich text")
        check(body.text.indexOf('href="https://example.com/guide"') >= 0, "Address was not linked: " + body.text)
        body.select(start, end)
        check(body.cursorSelection.font.underline, "Link is not underlined")
        body.select(end, end + 1)
        check(!body.cursorSelection.font.underline, "Trailing punctuation joined the link")
        body.deselect()
        body.cursorPosition = end
        body.insert(end, "xyz")
        window.linkifyContent()
        check(body.text.indexOf('href="https://example.com/guidexyz"') >= 0, "Editing an address did not update its link: " + body.text)
        // Type as a user would: key presses right after a link inherit its format.
        window.requestActivate()
        body.forceActiveFocus()
        input.wait(30)
        body.cursorPosition = end + 3
        input.keyClick(Qt.Key_Space)
        for (const character of "after") input.keyClick(character)
        window.linkifyContent()
        body.select(end + 4, end + 9)
        check(!body.cursorSelection.font.underline, "Text typed after a link became part of it")
        check(window.plainContent.indexOf(" after") > 0, "Linking changed the note text: " + JSON.stringify(window.plainContent))

        let clicked = ""
        const record = function(link) { clicked = link }
        window.linkClicked.connect(record)
        body.text = '<a href="file:///etc/hosts">local file</a> text'
        const rect = body.positionToRectangle(2)
        check(window.linkAt(rect.x + 2, rect.y + rect.height / 2) === "file:///etc/hosts", "No link under the click point")
        input.mouseClick(body, rect.x + 2, rect.y + rect.height / 2)
        window.linkClicked.disconnect(record)
        check(clicked === "file:///etc/hosts", "Clicking a link did not reach the handler: " + clicked)
        check(platformInfo.externalUrl(clicked) === "", "A file: link was allowed to open")
        // Past the end of the line is not on the link.
        const lineEnd = body.positionToRectangle(body.length)
        check(window.linkAt(lineEnd.x + 40, lineEnd.y + lineEnd.height / 2) === "", "Empty space opened a link")
        body.text = ""
    }

    function assertEditorFormatting(window) {
        const body = findItem(window.contentItem, "contentEditor")
        const original = "repeat repeat <b>literal</b> & İstanbul 🦀\nSecond line"
        body.text = original
        window.requestActivate()
        body.forceActiveFocus()
        input.wait(30)
        body.select(7, 13)
        clickTool(window, "boldButton")
        check(body.cursorSelection.font.bold, "Bold button did not format selected text")
        check(body.selectedText === "repeat", "Toolbar click lost selection")
        check(window.plainContent === original, "Formatting changed literal HTML or Unicode: " + JSON.stringify(body.getText(0, body.length)))
        body.select(0, 6)
        check(!body.cursorSelection.font.bold, "Formatting leaked into a repeated word")
        body.select(7, 13)
        input.keyClick(Qt.Key_B, Qt.ControlModifier)
        check(!body.cursorSelection.font.bold, "Ctrl+B did not toggle bold")
        input.keyClick(Qt.Key_B, Qt.ControlModifier)
        check(body.cursorSelection.font.bold, "Ctrl+B did not restore bold")
        clickTool(window, "italicButton")
        check(body.cursorSelection.font.bold && body.cursorSelection.font.italic, "Italic discarded bold")
        body.undo()
        check(body.cursorSelection.font.bold && !body.cursorSelection.font.italic, "Undo failed to preserve bold")
        body.redo()
        check(body.cursorSelection.font.italic, "Redo failed")
        body.select(7, 13)
        clickTool(window, "boldButton")
        check(!body.cursorSelection.font.bold && body.cursorSelection.font.italic, "Bold toggle cleared italic")
        clickTool(window, "underlineButton")
        window.applyTextColor("#ef4444", false)
        check(body.cursorSelection.font.underline && body.cursorSelection.font.italic, "Color cleared existing styles")
        check(body.cursorSelection.color.toString() === "#ef4444", "Text color not applied")
        window.applyTextColor("#000000", true)
        check(body.cursorSelection.font.underline && body.cursorSelection.font.italic, "Reset color cleared font styles")
        body.undo()
        check(body.cursorSelection.color.toString() === "#ef4444", "Reset color was not undoable")
        body.select(7, 13)
        clickTool(window, "heading1Button")
        check(body.cursorSelection.font.pixelSize === 26 && body.cursorSelection.font.bold, "H1 did not style selection: " + body.cursorSelection.font.pixelSize + " / " + body.cursorSelection.font.bold + " / " + body.selectedText)
        clickTool(window, "heading2Button")
        check(body.cursorSelection.font.pixelSize === 20, "H2 did not style selection")
        clickTool(window, "heading2Button")
        check(body.cursorSelection.font.pixelSize === 13, "H2 did not toggle back to body size")
        body.select(0, 6)
        check(body.cursorSelection.font.pixelSize === 13 && !body.cursorSelection.font.bold, "Heading changed adjacent text")
        body.deselect()
        const before = body.text
        window.toggleInlineStyle("b")
        window.toggleHeading(1)
        check(body.text === before, "No selection reused an old selection or inserted placeholder text")
        body.select(7, original.length)
        clickTool(window, "italicButton")
        check(window.plainContent === original, "Multiline formatting changed content")
        check(window.flush(), "Formatted note failed to save")
        const id = window.noteId
        window.close()
        window = library.openNote(id)
        const restored = findItem(window.contentItem, "contentEditor")
        check(window.plainContent === original, "Reopen lost rich text content")
        restored.select(7, 13)
        check(restored.cursorSelection.font.underline, "Reopen lost inline formatting")

        if (Qt.application.arguments.indexOf("--capture-ui") !== -1) {
            input.wait(30)
            input.grabImage(window.contentItem.parent).save("/tmp/betternotes-note.png")
        }
        const settings = window.settingsWindow
        settings.openCentered(window)
        settings.height = 680
        input.wait(30)
        const customButton = findItem(settings.contentItem, "customColorButton")
        input.mouseClick(customButton, customButton.width / 2, customButton.height / 2, Qt.LeftButton)
        input.wait(20)
        input.keyClick(Qt.Key_Escape)
        check(settings.visible, "Closing color picker closed settings")
        check(settings.chooseColor("#628c7a"), "Custom color save failed")
        check(window.noteTint === "#628c7a", "Custom color not reflected in note")
        settings.paletteIndex = 1
        input.wait(30)
        const swatch = findItem(settings.contentItem, "colorSwatch_#3b82f6")
        check(swatch, "Palette swatches missing")
        input.mouseClick(swatch, swatch.width / 2, swatch.height / 2, Qt.LeftButton)
        check(window.noteTint === "#3b82f6", "Palette click did not select color")
        const hex = findItem(settings.contentItem, "hexColorField")
        hex.text = "not-a-color"
        settings.applyHex()
        check(window.noteTint === "#3b82f6" && settings.appearanceError.length > 0, "Invalid custom color was accepted")
        hex.text = "8B5CF6"
        settings.applyHex()
        check(window.noteTint === "#8b5cf6" && settings.appearanceError.length === 0, "Valid custom color rejected")
        if (Qt.application.arguments.indexOf("--capture-ui") !== -1) {
            settings.width = 480
            settings.height = 680
            input.wait(30)
            input.grabImage(settings.contentItem).save("/tmp/betternotes-settings.png")
            const originalTheme = window.editorBackend.themeMode
            check(window.editorBackend.setThemeMode("dark"), "Dark preview failed")
            input.wait(30)
            input.grabImage(settings.contentItem).save("/tmp/betternotes-settings-dark.png")
            check(window.editorBackend.setThemeMode(originalTheme), "Restoring theme failed")
        }
        settings.width = settings.minimumWidth
        settings.height = settings.minimumHeight
        input.wait(30)
        const scroll = findItem(settings.contentItem, "settingsScroll")
        check(scroll.leftPadding >= 20 && scroll.contentWidth === scroll.availableWidth, "Settings content lost padding or overflows")
        settings.close()
        for (const size of [[240, 180], [800, 600], [260, 220], [380, 360]]) {
            window.width = size[0]
            window.height = size[1]
            input.wait(30)
            const toolbar = findItem(window.contentItem, "formatToolbar")
            const editorScroll = findItem(window.contentItem, "contentScroll")
            const imageButton = findItem(window.contentItem, "imageButton")
            const imageRight = imageButton.mapToItem(toolbar, imageButton.width, 0).x
            check(toolbar.width <= window.width - 20 && imageRight <= toolbar.width, "Toolbar overflow after resize")
            const editorBottom = editorScroll.mapToItem(window.contentItem, 0, editorScroll.height).y
            check(editorBottom <= window.contentItem.height, "Editor extends below window after resize")
            check(editorScroll.width > 0 && editorScroll.height >= 24, "Editor collapsed during resize")
            check(Math.abs(restored.width - editorScroll.availableWidth) < 1, "Editor width diverged from viewport")
        }
        window.toggleCollapsed()
        input.wait(20)
        window.toggleCollapsed()
        check(window.height === 360, "Collapse/expand lost resized height")
        window.close()
        window = library.openNote(id)
        check(window.noteTint === "#8b5cf6", "Selected palette color did not persist")
        check(window.deleteConfirmed(), "Formatting test cleanup failed")
    }

    // Tag chips, automatic lists, inserted and resized images, and GIFs that
    // play without counting as edits.
    function assertMediaAndLists(window) {
        const backend = window.editorBackend
        const body = findItem(window.contentItem, "contentEditor")
        const formatter = window.imageFormatter

        window.addTags("work, #rust")
        check(backend.tags.length === 2 && backend.tags[0] === "work" && backend.tags[1] === "rust", "Tags were not added as chips")
        window.addTags("Work")
        check(backend.tags.length === 2, "A duplicate tag was added")
        const tagInput = findItem(window.contentItem, "tagInput")
        tagInput.text = "desk"
        tagInput.accepted()
        check(backend.tags.length === 3 && tagInput.text === "", "Enter did not add the typed tag")
        window.removeTag(0)
        check(backend.tagsText === "rust, desk", "Removing a tag chip failed")

        body.forceActiveFocus()
        input.wait(10)
        for (const key of ["-", " ", "a"]) {
            input.keyClick(key)
            input.wait(1)
        }
        check(body.text.indexOf("<ul") >= 0 && window.plainContent === "a", "'- ' did not start a bulleted list")
        input.keyClick(Qt.Key_Return)
        input.keyClick(Qt.Key_Return)
        check((body.text.match(/<li/g) || []).length === 1, "Enter on an empty list item did not end the list")
        for (const key of ["1", ".", " ", "b"]) {
            input.keyClick(key)
            input.wait(1)
        }
        check(body.text.indexOf("<ol") >= 0, "'1. ' did not start a numbered list")
        body.select(0, body.length)
        body.remove(0, body.length)

        // The test points the XDG Pictures folder at its fixture images.
        const fixtures = backend.picturesFolder() + "/"
        check(fixtures.indexOf("/fixtures/") > 0, "Pictures folder not taken from the XDG user directories")
        check(window.insertImages([fixtures + "still.png", fixtures + "not-an-image.txt"], 0) === 1, "Image insert failed")
        const position = window.plainContent.indexOf("\ufffc")
        check(position >= 0 && body.text.indexOf("attachments/") >= 0, "Image was not stored as an attachment")
        check(formatter.imageAt(body.textDocument, position).width === 64, "A small image was scaled up")
        const rect = body.positionToRectangle(position)
        check(window.selectImageAt(rect.x + 4, rect.y + 4), "Clicking an image did not select it")
        const handle = findItem(window.contentItem, "imageResizeHandle")
        check(handle && handle.visible, "Image resize handle missing")
        input.mousePress(handle, handle.width / 2, handle.height / 2)
        input.mouseMove(handle, handle.width / 2 + 60, handle.height / 2)
        input.mouseRelease(handle, handle.width / 2 + 60, handle.height / 2)
        const resized = formatter.imageAt(body.textDocument, position)
        check(resized.width === 124 && resized.height === 62, "Dragging the handle did not resize the image in proportion")
        check(window.flush() && backend.draftContent.indexOf('width="124"') >= 0, "Resized image width was not saved")

        check(window.insertImages([fixtures + "animated.gif"], body.length) === 1, "GIF insert failed")
        check(window.imageAnimator.animationCount === 1, "GIF animation did not start")
        check(window.flush(), "GIF note failed to save")
        const gif = window.plainContent.lastIndexOf("\ufffc")
        const at = body.positionToRectangle(gif)
        const point = body.mapToItem(window.contentItem, at.x + 10, at.y + 10)
        const first = input.grabImage(window.contentItem).pixel(point.x, point.y)
        let changed = false
        for (let i = 0; i < 20 && !changed; ++i) {
            input.wait(30)
            changed = !Qt.colorEqual(input.grabImage(window.contentItem).pixel(point.x, point.y), first)
        }
        check(changed, "The GIF did not animate")
        check(!backend.dirty, "GIF frames were saved as edits")
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
                harness.library.libraryBackend.copyToClipboard("Desktop test")
                harness.check(harness.library.libraryBackend.getClipboardText() === "Desktop test", "Clipboard roundtrip failed")
                const initialAutostart = harness.library.libraryBackend.autostartEnabled
                harness.check(harness.library.libraryBackend.setAutostart(true), "Set autostart true failed")
                harness.check(harness.library.libraryBackend.autostartEnabled === true, "Autostart not enabled")
                harness.check(harness.library.libraryBackend.setAutostart(initialAutostart), "Restore autostart failed")
                harness.check(harness.library.libraryBackend.sendNotification("Test", "Desktop notification"), "Notification failed")
                harness.library.openQuickCapture()
                harness.check(harness.library.quickCaptureWindow !== null, "Quick capture window not created")
                harness.library.quickCaptureWindow.close()
                harness.first = harness.library.createNote()
                harness.second = harness.library.createNote()
                harness.check(harness.first && harness.second && harness.first !== harness.second, "Independent windows missing")
                harness.firstId = harness.first.noteId
                harness.secondId = harness.second.noteId
                harness.check(harness.first.transientParent === null && harness.second.transientParent === null, "Notes are transient windows")
                harness.check(harness.library.openNote(harness.firstId) === harness.first, "Duplicate editor created")
                harness.assertShowAllNotes(harness.library, [harness.firstId, harness.secondId])
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
                harness.check(harness.first.editorBackend.setPinned(true), "Set pinned failed")
                harness.check(harness.first.editorBackend.isPinned, "Pin status not updated")
                harness.check(harness.first.editorBackend.setPriority(2), "Set priority failed")
                harness.check(harness.first.editorBackend.priority === 2, "Priority status not updated")
                harness.check(harness.first.editorBackend.setTags("rust, desktop"), "Set tags failed")
                harness.check(harness.first.editorBackend.tagsText === "rust, desktop", "Tags text not updated")
                harness.first.flush()
                harness.library.libraryBackend.reload()
                harness.library.libraryBackend.search("İstanbul")
                harness.check(harness.library.libraryBackend.searchResultIds.length >= 1, "FTS search for Unicode content failed")
                harness.check(harness.library.libraryBackend.searchResultIds[0] === harness.firstId, "FTS search matched wrong note")
                harness.library.libraryBackend.search("desktop")
                harness.check(harness.library.libraryBackend.searchResultIds.length >= 1, "Search by tag failed")
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
                const linkNote = harness.library.createNote()
                harness.assertLinks(linkNote)
                harness.check(linkNote.deleteConfirmed(), "Link test note could not be deleted")
                const disposable = harness.library.createNote()
                harness.assertEditorFormatting(disposable)
                harness.check(harness.library.libraryBackend.titles.length === 2, "Delete failed to update library")
                const media = harness.library.createNote()
                harness.assertMediaAndLists(media)
                harness.check(media.deleteConfirmed(), "Media test note could not be deleted")
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
