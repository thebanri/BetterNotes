import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BetterNotes.App
import "../themes" as Themes
import "../components" as UI
import "WindowPlacement.js" as Placement

ApplicationWindow {
    id: noteWindow
    required property string noteId
    property alias editorBackend: backend
    property alias theme: theme
    property bool collapsed: false
    property bool initialized: false
    property bool retiring: false
    property bool placing: false
    property int expandedWidth: 380
    property int expandedHeight: 360
    property int normalX: 0
    property int normalY: 0
    property string normalScreen: ""
    readonly property bool canPosition: platformInfo.canPositionWindows(Qt.platform.pluginName)
    readonly property int collapsedHeight: 76

    signal saved()
    signal dismissed(string id)
    signal quitRequested()
    signal libraryRequested()

    // QObject ownership belongs to the library; these remain independent windows.
    transientParent: null
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowMinimizeButtonHint | Qt.WindowCloseButtonHint
    title: (titleEditor.text.trim().length ? titleEditor.text : qsTr("Untitled note")) + " — BetterNotes"
    width: 380
    height: 360
    minimumWidth: 240
    minimumHeight: collapsed ? collapsedHeight : 180
    maximumHeight: collapsed ? collapsedHeight : 16384
    visible: false
    color: theme.noteBackground

    Themes.Theme { id: theme; themeMode: backend.themeMode }
    NotesBackend { id: backend; objectName: "notesBackend" }
    ApplicationInfo { id: platformInfo }

    function present(fallbackScreen) {
        if (!backend.initializeNote(noteId)) return false
        collapsed = backend.savedCollapsed()
        place({x: backend.savedX(), y: backend.savedY(), width: backend.savedWidth(),
            height: backend.savedHeight(), screen: backend.savedScreen(),
            positioned: backend.savedPositioned()}, fallbackScreen, false)
        initialized = true
        show()
        if (!collapsed) titleEditor.forceActiveFocus()
        persist(true)
        return true
    }

    function place(state, fallbackScreen, recover) {
        const fitted = Placement.fit(state, Application.screens, fallbackScreen, recover)
        if (!fitted) return
        placing = true
        screen = fitted.screen
        expandedWidth = fitted.width
        expandedHeight = fitted.height
        width = expandedWidth
        height = collapsed ? collapsedHeight : expandedHeight
        if (canPosition && (state.positioned || recover)) {
            x = fitted.x
            y = fitted.y
        }
        normalX = x
        normalY = y
        normalScreen = screen.name
        placing = false
    }

    function recover(fallbackScreen) {
        showNormal()
        place({width: expandedWidth, height: expandedHeight, positioned: false}, fallbackScreen, true)
        persist(true)
        requestActivate()
    }

    function captureGeometry() {
        if (!initialized || placing || retiring || visibility !== Window.Windowed) return
        expandedWidth = width
        if (!collapsed) expandedHeight = height
        normalX = x
        normalY = y
        normalScreen = screen ? screen.name : ""
        geometrySave.restart()
    }

    function persist(open) {
        geometrySave.stop()
        return backend.saveWindow(normalX, normalY, expandedWidth, expandedHeight,
            normalScreen, collapsed, canPosition, open)
    }

    function flush() {
        // The installed Qt metadata exposes QObject without QInputMethod methods.
        // qmllint disable missing-property
        Qt.inputMethod.commit()
        // qmllint enable missing-property
        titleEditor.focus = false
        contentEditor.focus = false
        autosave.stop()
        const success = backend.save()
        if (success) saved()
        return success
    }

    function prepareQuit() { return flush() && persist(true) }

    function showDialog(dialog) {
        if (collapsed) toggleCollapsed()
        dialog.open()
    }

    function toggleCollapsed() {
        if (!collapsed && !flush()) return
        if (visibility !== Window.Windowed) showNormal()
        placing = true
        collapsed = !collapsed
        height = collapsed ? collapsedHeight : expandedHeight
        placing = false
        persist(true)
    }

    function deleteConfirmed() {
        if (!backend.deleteNote()) return false
        retiring = true
        saved()
        close()
        return true
    }

    onXChanged: captureGeometry()
    onYChanged: captureGeometry()
    onWidthChanged: captureGeometry()
    onHeightChanged: captureGeometry()
    onScreenChanged: captureGeometry()
    onClosing: function(close) {
        if (!retiring && (!flush() || !persist(false))) {
            close.accepted = false
            return
        }
        geometrySave.stop()
        autosave.stop()
        dismissed(noteId)
    }

    Connections {
        target: Application
        function onScreensChanged() {
            if (noteWindow.initialized && !noteWindow.retiring) {
                noteWindow.place({x: noteWindow.normalX, y: noteWindow.normalY,
                    width: noteWindow.expandedWidth, height: noteWindow.expandedHeight,
                    screen: noteWindow.normalScreen, positioned: noteWindow.canPosition},
                    noteWindow.screen, false)
                noteWindow.persist(true)
            }
        }
    }

    Timer { id: geometrySave; interval: 500; onTriggered: noteWindow.persist(true) }
    Timer {
        id: autosave
        interval: 500
        onTriggered: { if (backend.save()) noteWindow.saved() }
    }

    header: Rectangle {
        height: 40
        color: theme.noteHeader
        border.width: 1
        border.color: theme.noteBorder

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            UI.StyledButton {
                text: noteWindow.collapsed ? qsTr("Expand") : qsTr("Collapse")
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 28
                padding: 4
                leftPadding: 8
                rightPadding: 8
                onClicked: noteWindow.toggleCollapsed()
            }

            UI.StatusBadge {
                dirty: backend.dirty
                theme: noteWindow.theme
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            UI.StyledButton {
                text: backend.isPinned ? "📌" : "📍"
                theme: noteWindow.theme
                variant: backend.isPinned ? "accent" : "ghost"
                implicitHeight: 28
                padding: 4
                leftPadding: 6
                rightPadding: 6
                onClicked: {
                    backend.setPinned(!backend.isPinned)
                    autosave.restart()
                }
            }

            UI.StyledButton {
                text: qsTr("Menu")
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 28
                padding: 4
                leftPadding: 8
                rightPadding: 8
                onClicked: noteMenu.open()

                Menu {
                    id: noteMenu
                    MenuItem { text: qsTr("All notes"); onTriggered: noteWindow.libraryRequested() }
                    MenuItem {
                        text: backend.isPinned ? qsTr("Unpin note") : qsTr("Pin note")
                        onTriggered: { backend.setPinned(!backend.isPinned); autosave.restart() }
                    }
                    MenuItem {
                        text: backend.isArchived ? qsTr("Unarchive note") : qsTr("Archive note")
                        onTriggered: { backend.setArchived(!backend.isArchived); autosave.restart() }
                    }
                    MenuItem { text: qsTr("Save"); onTriggered: noteWindow.flush() && noteWindow.persist(true) }
                    MenuItem {
                        text: qsTr("Copy to clipboard")
                        onTriggered: {
                            backend.copyToClipboard(backend.draftContent)
                            backend.sendNotification(qsTr("Copied to clipboard"), backend.draftTitle || qsTr("Note content copied"))
                        }
                    }
                    MenuItem {
                        text: qsTr("Reload saved note")
                        onTriggered: { if (backend.dirty) noteWindow.showDialog(reloadDialog); else backend.reloadNote() }
                    }
                    MenuItem { text: qsTr("Delete note…"); onTriggered: noteWindow.showDialog(deleteDialog) }
                    MenuItem { text: qsTr("Close note"); onTriggered: noteWindow.close() }
                    MenuItem {
                        text: qsTr("Discard changes and close…")
                        enabled: backend.dirty || backend.errorMessage.length > 0 || backend.windowError.length > 0
                        onTriggered: noteWindow.showDialog(discardDialog)
                    }
                    MenuItem { text: qsTr("Quit BetterNotes"); onTriggered: noteWindow.quitRequested() }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8
        opacity: noteWindow.collapsed ? 0 : 1
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: theme.animShort }
        }

        Label {
            visible: backend.errorMessage.length > 0 || backend.windowError.length > 0
            text: backend.errorMessage || backend.windowError
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            color: theme.danger
            Accessible.role: Accessible.AlertMessage
        }

        TextField {
            id: titleEditor
            objectName: "titleEditor"
            visible: !noteWindow.collapsed
            Layout.fillWidth: true
            placeholderText: qsTr("Title")
            Accessible.name: qsTr("Note title")
            text: backend.draftTitle
            selectByMouse: true
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: theme.noteText
            placeholderTextColor: theme.noteTextSecondary
            selectionColor: theme.accent
            selectedTextColor: theme.accentText
            background: Rectangle {
                color: "transparent"
                border.width: titleEditor.activeFocus ? 1 : 0
                border.color: theme.border
                radius: theme.radiusSm
            }
            onTextEdited: { backend.editTitle(text); autosave.restart() }
        }

        RowLayout {
            visible: !noteWindow.collapsed
            Layout.fillWidth: true
            spacing: 6

            TextField {
                id: tagsEditor
                Layout.fillWidth: true
                placeholderText: qsTr("Tags (e.g. work, rust)...")
                Accessible.name: qsTr("Note tags")
                text: backend.tagsText
                selectByMouse: true
                font.pixelSize: 11
                color: theme.noteText
                placeholderTextColor: theme.noteTextSecondary
                background: Rectangle {
                    color: "transparent"
                    border.width: tagsEditor.activeFocus ? 1 : 0
                    border.color: theme.border
                    radius: theme.radiusSm
                }
                onEditingFinished: {
                    backend.setTags(text)
                    autosave.restart()
                }
            }

            UI.StyledButton {
                text: {
                    if (backend.priority === 3) return qsTr("High")
                    if (backend.priority === 2) return qsTr("Med")
                    if (backend.priority === 1) return qsTr("Low")
                    return qsTr("Priority")
                }
                theme: noteWindow.theme
                variant: backend.priority > 0 ? "accent" : "ghost"
                implicitHeight: 24
                padding: 2
                leftPadding: 6
                rightPadding: 6
                onClicked: {
                    const next = (backend.priority + 1) % 4
                    backend.setPriority(next)
                    autosave.restart()
                }
            }
        }

        ScrollView {
            visible: !noteWindow.collapsed
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            TextArea {
                id: contentEditor
                objectName: "contentEditor"
                text: backend.draftContent
                textFormat: TextEdit.PlainText
                placeholderText: qsTr("Write your note…")
                Accessible.name: qsTr("Note content")
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                font.pixelSize: 13
                color: theme.noteText
                placeholderTextColor: theme.noteTextSecondary
                selectionColor: theme.accent
                selectedTextColor: theme.accentText
                background: null
                onTextChanged: {
                    if (text !== backend.draftContent) {
                        backend.editContent(text)
                        autosave.restart()
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        anchors.centerIn: parent
        title: qsTr("Delete this note?")
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        Label { text: qsTr("The note and its unsaved edits will be deleted."); wrapMode: Text.WordWrap; width: Math.min(300, noteWindow.width - 64) }
        onAccepted: noteWindow.deleteConfirmed()
    }
    Dialog {
        id: discardDialog
        anchors.centerIn: parent
        title: qsTr("Discard changes and close?")
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        Label {
            text: qsTr("Unsaved text will be lost. If storage is unavailable, this window may reopen next time.")
            wrapMode: Text.WordWrap
            width: Math.min(300, noteWindow.width - 64)
        }
        onAccepted: {
            noteWindow.persist(false)
            noteWindow.retiring = true
            noteWindow.close()
        }
    }
    Dialog {
        id: reloadDialog
        anchors.centerIn: parent
        title: qsTr("Discard unsaved changes?")
        modal: true
        standardButtons: Dialog.Yes | Dialog.No
        Label { text: qsTr("Reload the saved note and discard this draft?"); wrapMode: Text.WordWrap; width: Math.min(300, noteWindow.width - 64) }
        onAccepted: backend.reloadNote()
    }
    Shortcut { sequences: [StandardKey.Save]; context: Qt.WindowShortcut; onActivated: noteWindow.flush() && noteWindow.persist(true) }
    Shortcut { sequences: [StandardKey.Close]; context: Qt.WindowShortcut; onActivated: noteWindow.close() }
    Shortcut { sequences: [StandardKey.Quit]; context: Qt.WindowShortcut; onActivated: noteWindow.quitRequested() }
}
