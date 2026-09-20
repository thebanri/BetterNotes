import QtQuick
import "qrc:/betternotes/windows" as UI

Item {
    id: harness
    property var window
    property var backend
    property var titleInput
    property var contentInput

    Component { id: mainWindow; UI.Main {} }

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

    Timer {
        interval: 10
        running: true
        onTriggered: {
            try {
                harness.window = mainWindow.createObject(null)
                harness.check(harness.window !== null, "Main window creation failed")
                for (let i = 0; i < harness.window.contentData.length; ++i) {
                    if (harness.window.contentData[i].objectName === "notesBackend")
                        harness.backend = harness.window.contentData[i]
                }
                harness.check(harness.backend && harness.backend.ready, "Database initialization failed")
                harness.titleInput = harness.findItem(harness.window.contentItem, "titleEditor")
                harness.contentInput = harness.findItem(harness.window.contentItem, "contentEditor")
                harness.check(harness.titleInput && harness.contentInput, "Missing editors")
                harness.check(harness.backend.createNote(), "Create failed")
                harness.titleInput.insert(0, "Autosaved title")
                harness.titleInput.textEdited()
                harness.contentInput.insert(0, "Plain <b>text</b>\nİstanbul 🦀")
                harness.check(harness.backend.dirty, "Edit did not mark draft dirty")
                verifyAutosave.start()
            } catch (error) {
                console.error(error)
                Qt.exit(1)
            }
        }
    }

    Timer {
        id: verifyAutosave
        interval: 800
        onTriggered: {
            try {
                harness.check(!harness.backend.dirty, "Autosave timer did not save")
                harness.check(harness.backend.titles[0] === "Autosaved title", "Title not saved")
                harness.check(harness.backend.createNote(), "Second create failed")
                harness.contentInput.insert(0, "Saved on switch")
                harness.check(harness.backend.selectNote(1), "Selection failed")
                harness.check(harness.titleInput.text === "Autosaved title", "Title binding lost")
                harness.check(harness.contentInput.text === "Plain <b>text</b>\nİstanbul 🦀", "Content binding lost or text interpreted as markup")
                harness.check(!harness.backend.dirty, "Selection dirtied the draft")
                harness.check(harness.backend.selectNote(0), "Second selection failed")
                harness.check(harness.contentInput.text === "Saved on switch", "Switch failed to persist draft")
                harness.check(harness.backend.deleteNote(), "Delete failed")
                harness.check(harness.backend.titles.length === 1, "Delete did not refresh list")
                harness.check(harness.backend.selectNote(0), "Remaining note missing")
                harness.contentInput.insert(harness.contentInput.length, "\nSaved on close")
                harness.check(harness.backend.dirty, "Close test needs a pending draft")
                harness.window.close()
                harness.check(!harness.backend.dirty, "Close did not flush draft")
                Qt.exit(0)
            } catch (error) {
                console.error(error)
                Qt.exit(1)
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: { console.error("QML test timed out"); Qt.exit(2) }
    }
}
