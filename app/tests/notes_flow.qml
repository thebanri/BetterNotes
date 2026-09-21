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

    // Search matches written text, never the HTML that formats it, and marks
    // the match; searches are remembered; notes export and import by URL.
    function assertSearchAndTransfer(library, note) {
        const backend = library.libraryBackend
        const body = findItem(note.contentItem, "contentEditor")
        body.text = "<p style=\"text-indent:0px\">zeppelin <b>margins</b> here</p>"
        check(note.flush(), "Search note did not save")
        backend.reload()
        backend.search("indent")
        check(backend.searchResultIds.indexOf(note.noteId) < 0, "Search matched HTML markup")
        backend.search("zeppelin")
        const at = backend.searchResultIds.indexOf(note.noteId)
        check(at >= 0, "Search did not find the note text")
        const snippet = backend.searchResultSnippets[at]
        check(snippet.indexOf("\ue000zeppelin\ue001") >= 0 && snippet.indexOf("<") < 0, "Snippet is not marked plain text: " + snippet)

        backend.clearRecentSearches()
        backend.rememberSearch("zeppelin")
        backend.rememberSearch("nginx")
        check(backend.recentSearches().length === 2 && backend.recentSearches()[0] === "nginx", "Recent searches not remembered")

        const folder = backend.picturesFolder() + "/"
        check(backend.exportNotesJson(folder + "export%20test.json"), "JSON export to a URL failed: " + backend.errorMessage)
        const existing = Array.from(backend.noteIds)
        check(backend.importNotesJson(folder + "export%20test.json") === existing.length, "Importing the export did not add every note")
        backend.reload()
        check(backend.noteIds.length === existing.length * 2, "Imported notes are missing from the library")
        check(backend.importNotesJson(folder + "missing.json") === -1 && backend.errorMessage.length > 0, "A missing import file was not reported")
        // Leave the library as it was for the checks that follow.
        const imported = Array.from(backend.noteIds).filter(function(id) { return existing.indexOf(id) < 0 })
        for (const id of imported) check(backend.deleteNoteById(id), "Could not remove an imported note")
        check(backend.noteIds.length === existing.length, "Imported notes were not cleaned up")
    }

    // Checklists, list indentation, alignment, counts, find and replace,
    // image preview, pasting and file attachments.
    function assertEditorExtras(window) {
        const fixtures = window.editorBackend.picturesFolder() + "/"
        const body = findItem(window.contentItem, "contentEditor")
        const formatter = window.imageFormatter
        const type = function(text) {
            for (const key of text) {
                input.keyClick(key === "\n" ? Qt.Key_Return : key)
                input.wait(1)
            }
        }
        body.forceActiveFocus()
        input.wait(10)

        // "[ ] " starts a checklist; Ctrl+Enter or a click on the box ticks it.
        type("[ ] milk")
        check(body.text.indexOf('class="unchecked"') >= 0 && window.plainContent === "milk", "'[ ] ' did not start a checklist")
        input.keyClick(Qt.Key_Return, Qt.ControlModifier)
        check(formatter.checkState(body.textDocument, 0) === 2, "Ctrl+Enter did not tick the item")
        input.keyClick(Qt.Key_End)
        type("\neggs")
        input.wait(5)
        check(formatter.checkState(body.textDocument, 5) === 1, "A new item after a ticked one started ticked")
        const box = body.positionToRectangle(5)
        check(window.toggleCheckAt(box.x - 12, box.y + box.height / 2), "Clicking the box did not tick it")
        check(formatter.checkState(body.textDocument, 5) === 2, "Clicking the box left it open")
        check(!window.toggleCheckAt(box.x + 10, box.y + box.height / 2), "Clicking the text ticked the box")

        // Tab nests an item, Shift+Tab brings it back.
        input.keyClick(Qt.Key_Tab)
        check(body.text.indexOf("-qt-list-indent: 2") >= 0, "Tab did not nest the list item")
        input.keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        check(body.text.indexOf("-qt-list-indent: 2") < 0, "Shift+Tab did not bring the item back")
        check(formatter.checkState(body.textDocument, 5) === 2, "Indenting lost the tick")

        // Alignment and counts.
        body.text = ""
        type("one two three")
        window.align("center")
        check(window.alignment() === "center" && body.text.indexOf('align="center"') >= 0, "Centering failed")
        window.align("left")
        const stats = window.textStats()
        check(stats.words === 3 && stats.characters === 13, "Word count wrong: " + JSON.stringify(stats))

        // Find and replace.
        body.text = ""
        type("cat Cat cAt dog")
        window.openFind(true)
        const bar = window.findBarItem
        check(bar.visible, "Find bar did not open")
        bar.query = "cat"
        check(window.findMatches.length === 3 && body.selectedText.toLowerCase() === "cat", "Find did not match case-insensitively")
        bar.caseSensitive = true
        check(window.findMatches.length === 1, "Match case did not narrow the matches")
        bar.caseSensitive = false
        bar.replacement = "bird"
        window.replaceCurrent()
        check(window.findMatches.length === 2 && window.plainContent.split("bird").length === 2, "Replace did not change one match")
        check(window.replaceAll() === 2 && window.plainContent === "bird bird bird dog", "Replace all failed: " + window.plainContent)
        window.closeFind()
        check(!bar.visible, "Find bar did not close")

        // Pasting text is untouched by image paste.
        window.editorBackend.copyToClipboard("plain words")
        check(!window.pasteImages(), "Plain text was taken for an image")

        // Files other than images are attachments: listed, opened only when
        // they cannot run as programs, and removed with their stored copy.
        check(window.attachFiles([fixtures + "notes.txt", fixtures + "tool.sh"]) === 2, "Attaching files failed")
        check(window.attachments.length === 2, "Attachments not listed: " + JSON.stringify(window.attachments))
        const text = window.attachments.find(function(a) { return a.name === "notes.txt" })
        const script = window.attachments.find(function(a) { return a.name === "tool.sh" })
        check(text && text.openable && window.editorBackend.attachmentOpenUrl(text.id).length > 0, "A text attachment cannot be opened")
        check(script && !script.openable && window.editorBackend.attachmentOpenUrl(script.id) === "", "A script attachment could be opened")
        check(window.editorBackend.saveImageAs(text.url, fixtures + "saved-notes.txt"), "Saving an attachment failed")
        check(window.editorBackend.removeAttachment(script.id), "Removing an attachment failed")
        check(!window.editorBackend.removeAttachment("not-an-id"), "Removed an attachment the note does not have")
        window.refreshAttachments()
        check(window.attachments.length === 1, "Removed attachment still listed")

        // Double-clicking an image opens it full size.
        body.text = ""
        check(window.insertImages([fixtures + "still.png"], 0) === 1, "Image insert failed")
        check(window.attachments.length === 1, "An inline image was listed as a file attachment")
        const imageAt = body.positionToRectangle(window.plainContent.indexOf("\ufffc"))
        check(window.selectImageAt(imageAt.x + 4, imageAt.y + 4), "Image not selectable")
        window.previewSelectedImage()
        check(window.imagePreviewWindow.visible && window.imagePreviewWindow.name === "still.png", "Image preview did not open")
        window.imagePreviewWindow.close()
    }

    // Deleted notes go to the trash and come back; several notes can be
    // selected and tagged, trashed or deleted for good at once.
    function assertTrashAndSelection(library) {
        const backend = library.libraryBackend
        const make = function(title) {
            const sticky = library.createNote()
            findItem(sticky.contentItem, "titleEditor").text = title
            sticky.editorBackend.editTitle(title)
            check(sticky.flush(), "Could not save " + title)
            const id = sticky.noteId
            sticky.close()
            backend.reload()
            return id
        }
        const a = make("Trash A")
        const b = make("Trash B")
        const c = make("Trash C")

        library.noteAction(a, "delete")
        check(backend.noteIds.indexOf(a) < 0 && backend.trashIds.indexOf(a) >= 0, "Delete did not move the note to the trash")
        library.showSection("trash")
        check(library.visibleNotes.some(function(n) { return n.id === a && n.trashed }), "Trash section does not list the note")
        library.noteAction(a, "restore-trash")
        check(backend.noteIds.indexOf(a) >= 0 && backend.trashIds.indexOf(a) < 0, "Restore did not bring the note back")

        library.showSection("all")
        library.toggleSelected(a, false)
        library.toggleSelected(c, true)
        check(library.selectionCount === 3, "Shift range did not select the notes between: " + library.selectionCount)
        library.toggleSelected(b, false)
        check(library.selectionCount === 2, "Ctrl click did not deselect")
        library.bulkTag("bulk")
        check(library.selectionCount === 0, "Selection stayed after tagging")
        for (const id of [a, c]) {
            check(library.noteTagsAt(backend.noteIds.indexOf(id)).indexOf("bulk") >= 0, "Bulk tag missing on a note")
        }
        check(library.noteTagsAt(backend.noteIds.indexOf(b)).indexOf("bulk") < 0, "Bulk tag reached an unselected note")

        for (const id of [a, b, c]) library.toggleSelected(id, false)
        library.bulkAction("delete")
        check([a, b, c].every(function(id) { return backend.trashIds.indexOf(id) >= 0 }), "Bulk move to trash failed")
        library.showSection("trash")
        library.selectAllVisible()
        library.bulkAction("delete-forever")
        const dialog = library.deleteForeverDialog
        check(dialog.visible && dialog.noteIds.length >= 3, "Delete for good did not ask first")
        dialog.accept()
        check([a, b, c].every(function(id) { return backend.trashIds.indexOf(id) < 0 }), "Delete for good left notes in the trash")
        library.showSection("all")
    }

    // Arranging lines the open notes up without overlap on the library's
    // screen. The offscreen platform places windows, as X11 does.
    function assertArrangeAndOpenFiles(library) {
        const ids = Object.keys(library.noteWindows)
        check(ids.length >= 1, "No open notes to arrange")
        const first = library.noteWindows[ids[0]]
        first.x = 5000
        first.y = 5000
        check(library.arrangeNotes() === "arranged", "Arranging was not possible")
        const rects = ids.map(function(id) {
            const w = library.noteWindows[id]
            return { x: w.x, y: w.y, width: w.width, height: w.height }
        })
        for (let i = 0; i < rects.length; ++i) {
            const a = rects[i]
            check(a.x >= library.screen.virtualX && a.x < library.screen.virtualX + library.screen.width, "A note was left off screen")
            for (let j = i + 1; j < rects.length; ++j) {
                const b = rects[j]
                const overlap = a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
                check(!overlap, "Arranged notes overlap")
            }
        }

        // Files opened with BetterNotes become notes.
        const backend = library.libraryBackend
        const folder = backend.picturesFolder().replace("file://", "")
        const opened = backend.openFiles([folder + "/notes.txt", folder + "/still.png", folder + "/missing.txt"])
        check(opened.length === 2, "Opening files made " + opened.length + " notes")
        check(backend.errorMessage.indexOf("missing.txt") >= 0, "A file that could not be opened was not reported")
        for (const id of opened) {
            const i = backend.noteIds.indexOf(id)
            check(i >= 0, "An opened file's note is not listed")
            check(backend.deleteNoteById(id), "Could not clean up an opened note")
        }
    }

    // Backup settings save, and Back Up Now writes a complete backup.
    function assertBackups(library) {
        const backend = library.libraryBackend
        const defaults = JSON.parse(backend.autoBackupSettings())
        check(defaults.enabled && defaults.interval === "daily" && defaults.keep === 7, "Unexpected backup defaults")
        const folder = backend.picturesFolder() + "/backups"
        check(backend.setAutoBackupSettings(true, "weekly", 3, folder), "Saving backup settings failed")
        const saved = JSON.parse(backend.autoBackupSettings())
        check(saved.interval === "weekly" && saved.keep === 3 && saved.target.endsWith("/fixtures/backups"), "Backup settings not saved: " + JSON.stringify(saved))
        check(!backend.setAutoBackupSettings(true, "daily", 3, "relative/path"), "A relative backup folder was accepted")
        const made = backend.backupNow()
        check(made.indexOf("/fixtures/backups/betternotes-backup-") >= 0, "Back Up Now failed: " + backend.errorMessage)
        check(JSON.parse(backend.autoBackupSettings()).last > 0, "Last backup time not recorded")
        library.settingsPopupItem.open()
        check(findItem(library.settingsPopupItem.contentItem, "backupSection").visible, "Settings show no backup section")
        library.settingsPopupItem.close()
    }

    // Accent colours and themes reach open notes; shortcuts change, refuse
    // conflicts and reset.
    function assertAppearanceAndShortcuts(library) {
        const backend = library.libraryBackend
        const sticky = library.createNote()
        check(backend.setAccentColor("#14b8a6"), "Setting the accent failed")
        check(Qt.colorEqual(library.theme.accent, "#14b8a6") && Qt.colorEqual(sticky.theme.accent, "#14b8a6"), "The accent did not reach the open note")
        check(!backend.setAccentColor("teal"), "An invalid accent was accepted")
        check(backend.setThemeMode("sepia") && !sticky.theme.isDark && sticky.theme.isSepia, "Sepia theme did not reach the note")
        check(backend.setThemeMode("black") && sticky.theme.isDark && Qt.colorEqual(library.theme.windowBackground, "#000000"), "Black theme failed")
        check(backend.setThemeMode("system") && backend.setAccentColor("#6366f1"), "Could not restore the appearance")

        check(backend.setShortcut("bold", "Ctrl+Shift+B") === "", "Changing a shortcut failed")
        check(sticky.keys.bold === "Ctrl+Shift+B", "The new shortcut did not reach the open note")
        check(backend.setShortcut("italic", "Ctrl+Shift+B").length > 0, "A conflicting shortcut was accepted")
        const recorder = library.keySequencesItem
        check(recorder.fromKey(Qt.Key_B, Qt.ControlModifier | Qt.ShiftModifier) === "Ctrl+Shift+B", "Key recording text is wrong")
        check(recorder.fromKey(Qt.Key_Control, Qt.ControlModifier) === "", "A lone modifier was recorded")
        check(backend.resetShortcuts() && sticky.keys.bold === "Ctrl+B", "Resetting shortcuts failed")
        check(sticky.deleteConfirmed(), "Could not clean up the appearance note")
    }

    // Locking a note sets up the password first; locked notes close when
    // locked, ask for the password to open, and can have the lock removed.
    function assertLockedNotes(library) {
        const backend = library.libraryBackend
        const dialog = library.passwordDialogItem
        const field = function(name) { return findItem(dialog.contentItem, name) }
        let sticky = library.createNote()
        const id = sticky.noteId
        findItem(sticky.contentItem, "contentEditor").insert(0, "secret words")
        check(sticky.flush(), "Could not save the note to lock")

        library.noteAction(id, "lock")
        check(dialog.visible && dialog.mode === "setup", "Locking without a password did not ask to set one")
        field("passwordFirst").text = "short"
        field("passwordSecond").text = "short"
        dialog.submit()
        check(dialog.visible && dialog.error.length > 0, "A short password was accepted")
        field("passwordFirst").text = "correct horse"
        field("passwordSecond").text = "correct horsE"
        dialog.submit()
        check(dialog.visible && dialog.error.length > 0, "Mismatched passwords were accepted")
        field("passwordSecond").text = "correct horse"
        dialog.submit()
        check(!dialog.visible && backend.vaultSet && backend.vaultUnlocked, "Setting the password failed")
        check(sticky.editorBackend.isLocked && library.isLockedNote(id), "The note was not locked after setting the password")
        backend.search("secret")
        check(backend.searchResultIds.indexOf(id) < 0, "A locked note's text is searchable")

        library.lockNow()
        check(!backend.vaultUnlocked && !library.noteWindows[id], "Lock Now left the locked note open")
        check(library.openNote(id) === null && dialog.visible && dialog.mode === "unlock", "Opening a locked note did not ask for the password")
        field("passwordFirst").text = "wrong password"
        dialog.submit()
        check(dialog.visible && dialog.error.length > 0 && !backend.vaultUnlocked, "A wrong password unlocked")
        field("passwordFirst").text = "correct horse"
        dialog.submit()
        sticky = library.noteWindows[id]
        check(sticky && sticky.plainContent === "secret words", "Unlocking did not open the note with its text")

        library.noteAction(id, "unlock-note")
        check(!sticky.editorBackend.isLocked && !library.isLockedNote(id), "Removing the lock failed")
        check(sticky.deleteConfirmed(), "Could not clean up the locked note")
    }

    // The interface switches to Turkish and back without a restart.
    function assertLanguage(library) {
        const backend = library.libraryBackend
        check(backend.setLanguage("tr"), "Choosing Turkish failed")
        library.applyLanguage()
        check(library.sectionTitle === "Tüm notlar", "The library did not switch to Turkish: " + library.sectionTitle)
        check(qsTranslate("NoteCard", "Deleted %n day(s) ago", "", 3) === "3 gün önce silindi", "Turkish plural form missing")
        check(!backend.setLanguage("klingon"), "An unknown language was accepted")
        check(backend.setLanguage("en"), "Choosing English failed")
        library.applyLanguage()
        check(library.sectionTitle === "All notes", "The library did not switch back to English")
        check(qsTranslate("NoteCard", "Deleted %n day(s) ago", "", 1) === "Deleted 1 day ago", "English singular form missing")
        check(qsTranslate("NoteCard", "Deleted %n day(s) ago", "", 2) === "Deleted 2 days ago", "English plural form missing")
        check(backend.setLanguage("system"), "Choosing the system language failed")
        library.applyLanguage()
    }

    // A reminder set on a note shows in the library, can be edited there and
    // fires once when due.
    function assertReminders(library, note) {
        const id = note.noteId
        const tomorrow = new Date()
        tomorrow.setDate(tomorrow.getDate() + 1)
        const date = tomorrow.getFullYear() + "-" + String(tomorrow.getMonth() + 1).padStart(2, "0")
            + "-" + String(tomorrow.getDate()).padStart(2, "0")
        const field = function(editor, name) { return findItem(editor.contentItem, name) }

        note.editReminder()
        const editor = note.reminderEditor
        check(editor.visible && !editor.hasReminder, "Reminder editor did not open")
        field(editor, "reminderDate").text = "2020-01-01"
        field(editor, "reminderTime").text = "09:00"
        editor.save()
        check(editor.visible && editor.error.length > 0, "A reminder in the past was accepted")
        field(editor, "reminderDate").text = date.replace(/-\d\d$/, "-32")
        editor.save()
        check(editor.visible && editor.error.length > 0, "An impossible date was accepted")
        field(editor, "reminderDate").text = date
        field(editor, "reminderTime").text = "09:30"
        field(editor, "reminderRepeat").currentIndex = 2
        editor.save()
        check(!editor.visible && note.reminder.endsWith("|weekly"), "Saving a reminder failed")
        const expected = new Date(tomorrow.getFullYear(), tomorrow.getMonth(), tomorrow.getDate(), 9, 30)
        check(parseInt(note.reminder) === expected.getTime() / 1000, "Reminder time is not the local time entered")
        const headerChip = findItem(note.header, "headerReminder")
        check(headerChip && headerChip.visible, "The title bar does not show the reminder")

        const backend = library.libraryBackend
        const index = backend.noteIds.indexOf(id)
        check(backend.noteReminders[index] === note.reminder, "The library does not list the reminder")
        check(library.countNotes("reminders") === 1, "Reminders section count is wrong")
        library.showSection("reminders")
        check(library.visibleNotes.length === 1 && library.visibleNotes[0].id === id, "Reminders section shows the wrong notes")
        library.showSection("all")

        library.editReminder(id)
        const libraryEditor = library.reminderEditorItem
        check(libraryEditor.visible && libraryEditor.hasReminder, "Library reminder editor did not open")
        check(field(libraryEditor, "reminderTime").text === "09:30", "Library editor lost the saved time")
        field(libraryEditor, "reminderRepeat").currentIndex = 0
        libraryEditor.save()
        check(note.reminder.endsWith("|none"), "Editing in the library did not reach the open note")
        library.editReminder(id)
        libraryEditor.removeRequested()
        libraryEditor.close()
        check(note.reminder === "" && backend.noteReminders[index] === "", "Removing the reminder failed")

        // Due reminders fire once; a one-time reminder is then gone.
        check(backend.setNoteReminder(id, Math.floor(Date.now() / 1000) - 5, "none"), "Setting a due reminder failed")
        check(backend.checkReminders() === 1, "The due reminder did not fire")
        check(backend.checkReminders() === 0 && backend.noteReminders[index] === "", "A one-time reminder fired twice")
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

        // Starting an empty note with a list hides the placeholder hint,
        // which would otherwise sit over the first bullet.
        body.text = ""
        check(body.length === 0 && body.placeholderText.length > 0, "An empty note lost its hint")
        clickTool(window, "bulletListButton")
        check(body.length === 0 && body.placeholderText === "", "The hint covers the bullet of an empty list")
        clickTool(window, "bulletListButton")
        check(body.placeholderText.length > 0, "The hint did not return after removing the list")
        // "Default" is the desktop's font, never the monospace fallback an
        // empty family resolves to.
        check(body.font.family === Qt.application.font.family, "Default note font is not the desktop font")

        // ``` then Enter starts a code block, Enter continues it, and ``` on
        // a line of its own ends it; the block survives saving and reopening.
        body.text = ""
        body.forceActiveFocus()
        const typeText = function(text) {
            for (const key of text) {
                input.keyClick(key === "\n" ? Qt.Key_Return : key)
                input.wait(1)
            }
        }
        typeText("```\nlet x = 1;\n- y\n```\nafter")
        check(window.plainContent === "let x = 1;\n- y\nafter", "Fences were not consumed: " + JSON.stringify(window.plainContent))
        const codeLine = function(line) {
            const at = window.plainContent.split("\n").slice(0, line).join("\n").length + (line > 0 ? 1 : 0)
            return formatter.codeActive(body.textDocument, at, at)
        }
        check(codeLine(0) && codeLine(1), "Lines typed after ``` are not code")
        check(body.text.indexOf("<li") < 0, "Typing - inside a code block started a list")
        body.select(1, 2)
        check(body.cursorSelection.font.family === "monospace", "Text typed in a code block is not monospace")
        const afterAt = window.plainContent.indexOf("after")
        body.select(afterAt + 1, afterAt + 2)
        check(body.cursorSelection.font.family !== "monospace", "Text typed after the code block is still monospace")
        check(!codeLine(2), "``` did not end the code block")
        input.wait(20)
        let boxes = 0
        for (let i = 0; i < body.children.length; ++i) if (body.children[i].objectName === "codeBox") ++boxes
        check(boxes === 1, "The code block has no box behind it")
        const copyButton = findItem(body, "copyCodeButton")
        check(copyButton, "The code block has no copy button")
        input.mouseClick(copyButton, copyButton.width / 2, copyButton.height / 2)
        check(window.editorBackend.getClipboardText() === "let x = 1;\n- y", "Copy code copied: " + JSON.stringify(window.editorBackend.getClipboardText()))
        check(body.text.indexOf("rgba(128,128,128") >= 0 && body.text.indexOf("monospace") >= 0, "Code block formatting is not saved")
        body.select(0, 0)
        check(window.codeActive(), "Code button does not show the code block")
        clickTool(window, "codeBlockButton")
        check(!codeLine(0) && codeLine(1), "The code button did not turn the caret's line back into text")
        body.text = ""

        // The toolbar buttons turn existing lines into a list and back.
        // The note is rich text by now, so each line is its own paragraph,
        // as pressing Enter makes them.
        body.insert(0, "<p>milk</p><p>eggs</p><p>bread</p>")
        body.select(0, body.length)
        clickTool(window, "bulletListButton")
        check((body.text.match(/<li/g) || []).length === 3 && body.text.indexOf("<ul") >= 0, "Bulleted list button did not list every selected line")
        check(window.listActive("bullet") && !window.listActive("number"), "Bulleted list button state is wrong")
        clickTool(window, "numberedListButton")
        check(body.text.indexOf("<ol") >= 0 && body.text.indexOf("<ul") < 0, "Numbered list did not replace the bullets")
        clickTool(window, "numberedListButton")
        check(body.text.indexOf("<li") < 0 && window.plainContent === "milk\neggs\nbread", "Toggling the list off changed the text")
        body.deselect()
        body.cursorPosition = 6
        clickTool(window, "bulletListButton")
        check((body.text.match(/<li/g) || []).length === 1, "Without a selection only the caret's line should become a list item")
        body.select(0, body.length)
        body.remove(0, body.length)

        // The test points the XDG Pictures folder at its fixture images.
        const fixtures = backend.picturesFolder() + "/"
        check(fixtures.indexOf("/fixtures/") > 0, "Pictures folder not taken from the XDG user directories")
        check(window.insertImages([fixtures + "still.png", fixtures + "not-an-image.txt"], 0) === 1, "Image insert failed")
        const position = window.plainContent.indexOf("\ufffc")
        check(position >= 0 && body.text.indexOf("attachments/") >= 0, "Image was not stored as an attachment")
        check(formatter.imageAt(body.textDocument, position).width === 64, "A small image was scaled up")
        input.wait(30)
        const stillAt = body.positionToRectangle(position)
        const stillPoint = body.mapToItem(window.contentItem, stillAt.x + 20, stillAt.y + 10)
        const stillColor = input.grabImage(window.contentItem).pixel(stillPoint.x, stillPoint.y)
        check(stillColor.r > 0.9 && stillColor.g < 0.1 && stillColor.b < 0.1, "A palette PNG was not drawn in its colours: " + stillColor)
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

        body.deselect()
        const imageRect = body.positionToRectangle(position)
        input.mouseClick(body, imageRect.x + 4, imageRect.y + 4, Qt.RightButton)
        check(window.imageMenu.visible && window.selectedImage === position, "Right-clicking an image did not open its menu")
        window.imageMenu.close()
        const stored = formatter.imageAt(body.textDocument, position).name
        check(backend.imageFileName(stored) === "still.png", "Save did not suggest the original file name")
        check(backend.saveImageAs(stored, fixtures + "saved.png"), "Saving the image failed")
        check(window.copySelectedImage(), "Copy Image failed")
        check(backend.clipboardFileUrls().indexOf("attachments/") >= 0, "The copied image is not on the clipboard")
        check(!backend.copyImage("https://example.com/x.png"), "Copied a remote image")
        check(!backend.saveImageAs(stored, "https://example.com/x.png"), "Saved to a non-local URL")

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
        const frame = input.grabImage(window.contentItem).pixel(point.x, point.y)
        check((frame.r > 0.9 || frame.b > 0.9) && frame.g < 0.1, "GIF frames were not drawn in their colours: " + frame)
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
                harness.assertReminders(harness.library, media)
                harness.assertSearchAndTransfer(harness.library, media)
                harness.assertTrashAndSelection(harness.library)
                harness.assertArrangeAndOpenFiles(harness.library)
                harness.assertBackups(harness.library)
                harness.assertAppearanceAndShortcuts(harness.library)
                harness.assertLockedNotes(harness.library)
                harness.assertLanguage(harness.library)
                const extras = harness.library.createNote()
                harness.assertEditorExtras(extras)
                harness.check(extras.deleteConfirmed(), "Editor extras note could not be deleted")
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
        // A safety net for a hung test only: the run takes a few seconds, and
        // password hashing is slow in debug builds on shared CI machines.
        interval: 60000
        running: true
        onTriggered: { console.error("QML test timed out"); Qt.exit(2) }
    }
}
