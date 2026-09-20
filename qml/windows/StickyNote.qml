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
    readonly property int collapsedHeight: 38

    signal saved()
    signal dismissed(string id)
    signal quitRequested()
    signal libraryRequested()
    signal newNoteRequested()

    property bool alwaysOnTop: false
    property string noteTint: "yellow"
    readonly property var tintPalettes: ({
        "yellow": {
            bg: theme.isDark ? "#28231a" : "#fefce8",
            header: theme.isDark ? "#362f23" : "#fef08a",
            border: theme.isDark ? "#4f4230" : "#fde047"
        },
        "green": {
            bg: theme.isDark ? "#17271c" : "#f0fdf4",
            header: theme.isDark ? "#1e3727" : "#dcfce7",
            border: theme.isDark ? "#2e573c" : "#86efac"
        },
        "pink": {
            bg: theme.isDark ? "#2d161d" : "#fff1f2",
            header: theme.isDark ? "#3d1c26" : "#ffe4e6",
            border: theme.isDark ? "#5c2738" : "#fda4af"
        },
        "blue": {
            bg: theme.isDark ? "#142436" : "#f0f9ff",
            header: theme.isDark ? "#1a324b" : "#e0f2fe",
            border: theme.isDark ? "#254e77" : "#7dd3fc"
        },
        "purple": {
            bg: theme.isDark ? "#241834" : "#faf5ff",
            header: theme.isDark ? "#32204a" : "#f3e8ff",
            border: theme.isDark ? "#4c2f70" : "#d8b4fe"
        }
    })
    readonly property color activeBg: tintPalettes[noteTint] ? tintPalettes[noteTint].bg : theme.noteBackground
    readonly property color activeHeader: tintPalettes[noteTint] ? tintPalettes[noteTint].header : theme.noteHeader
    readonly property color activeBorder: tintPalettes[noteTint] ? tintPalettes[noteTint].border : theme.noteBorder

    // QObject ownership belongs to the library; these remain independent windows.
    transientParent: null
    flags: Qt.Window | Qt.FramelessWindowHint | (alwaysOnTop ? Qt.WindowStaysOnTopHint : 0)
    title: (titleEditor.text.trim().length ? titleEditor.text : qsTr("Untitled note")) + " — BetterNotes"
    width: 380
    height: 360
    minimumWidth: 240
    minimumHeight: collapsed ? collapsedHeight : 180
    maximumHeight: collapsed ? collapsedHeight : 16384
    visible: false
    color: activeBg

    Themes.Theme { id: theme; themeMode: backend.themeMode }
    NotesBackend { id: backend; objectName: "notesBackend" }
    ApplicationInfo { id: platformInfo }

    function present(fallbackScreen) {
        if (!backend.initializeNote(noteId)) return false
        collapsed = backend.savedCollapsed()
        const savedColor = backend.noteColor()
        if (savedColor && savedColor.length > 0) noteTint = savedColor
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
        if (state.positioned || recover || canPosition) {
            x = fitted.x
            y = fitted.y
        }
        normalX = (x !== 0 || y !== 0) ? x : (state.x || fitted.x)
        normalY = (x !== 0 || y !== 0) ? y : (state.y || fitted.y)
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
        if (x !== 0 || y !== 0) {
            normalX = x
            normalY = y
        }
        normalScreen = screen ? screen.name : ""
        geometrySave.restart()
    }

    function persist(open) {
        geometrySave.stop()
        const isPositioned = (normalX !== 0 || normalY !== 0)
        return backend.saveWindow(normalX, normalY, expandedWidth, expandedHeight,
            normalScreen, collapsed, isPositioned, open)
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
        height: 38
        color: activeHeader
        border.width: 1
        border.color: activeBorder

        MouseArea {
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.LeftButton
            onPressed: noteWindow.startSystemMove()
            onDoubleClicked: noteWindow.toggleCollapsed()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 6
            z: 1

            UI.StyledButton {
                text: "＋"
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 26
                implicitWidth: 26
                padding: 0
                font.pixelSize: 14
                font.weight: Font.Bold
                onClicked: noteWindow.newNoteRequested()
            }

            UI.StyledButton {
                text: noteWindow.collapsed ? "▼" : "▲"
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 26
                implicitWidth: 26
                padding: 0
                font.pixelSize: 10
                onClicked: noteWindow.toggleCollapsed()
            }

            UI.StatusBadge {
                dirty: backend.dirty
                theme: noteWindow.theme
                Layout.alignment: Qt.AlignVCenter
            }

            Label {
                Layout.fillWidth: true
                text: noteWindow.collapsed ? (titleEditor.text.trim() || qsTr("Untitled note")) : ""
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: theme.noteText
                elide: Text.ElideRight
                visible: noteWindow.collapsed
            }

            Item {
                Layout.fillWidth: true
                visible: !noteWindow.collapsed
            }

            UI.StyledButton {
                text: noteWindow.alwaysOnTop ? "📌" : "📍"
                theme: noteWindow.theme
                variant: noteWindow.alwaysOnTop ? "accent" : "ghost"
                implicitHeight: 26
                implicitWidth: 26
                padding: 0
                onClicked: {
                    noteWindow.alwaysOnTop = !noteWindow.alwaysOnTop
                }
            }

            UI.StyledButton {
                text: "⋮"
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 26
                implicitWidth: 26
                padding: 0
                font.pixelSize: 14
                font.weight: Font.Bold
                onClicked: noteMenu.open()

                Menu {
                    id: noteMenu
                    Menu {
                        title: qsTr("🎨 Note color")
                        MenuItem { text: qsTr("🟡 Classic Yellow"); onTriggered: { noteWindow.noteTint = "yellow"; backend.setNoteColor("yellow") } }
                        MenuItem { text: qsTr("🟢 Mint Green"); onTriggered: { noteWindow.noteTint = "green"; backend.setNoteColor("green") } }
                        MenuItem { text: qsTr("🌸 Rose Pink"); onTriggered: { noteWindow.noteTint = "pink"; backend.setNoteColor("pink") } }
                        MenuItem { text: qsTr("🔵 Sky Blue"); onTriggered: { noteWindow.noteTint = "blue"; backend.setNoteColor("blue") } }
                        MenuItem { text: qsTr("🟣 Lavender Purple"); onTriggered: { noteWindow.noteTint = "purple"; backend.setNoteColor("purple") } }
                    }
                    MenuSeparator {}
                    MenuItem { text: qsTr("All notes (Library)"); onTriggered: noteWindow.libraryRequested() }
                    MenuItem {
                        text: backend.isPinned ? qsTr("Unpin from favorites") : qsTr("Pin to favorites")
                        onTriggered: { backend.setPinned(!backend.isPinned); autosave.restart() }
                    }
                    MenuItem {
                        text: backend.isArchived ? qsTr("Unarchive note") : qsTr("Archive note")
                        onTriggered: { backend.setArchived(!backend.isArchived); autosave.restart() }
                    }
                    MenuItem {
                        text: noteWindow.alwaysOnTop ? qsTr("✓ Always on top") : qsTr("Always on top")
                        onTriggered: noteWindow.alwaysOnTop = !noteWindow.alwaysOnTop
                    }
                    MenuItem {
                        text: qsTr("⏰ Remind in 1 hour")
                        onTriggered: {
                            const nowSec = Math.round(Date.now() / 1000)
                            backend.setReminder(nowSec + 3600, "none")
                            backend.sendNotification(qsTr("Reminder set"), qsTr("We will remind you in 1 hour."))
                        }
                    }
                    MenuItem {
                        text: qsTr("⏰ Remind tomorrow (daily)")
                        onTriggered: {
                            const nowSec = Math.round(Date.now() / 1000)
                            backend.setReminder(nowSec + 86400, "daily")
                            backend.sendNotification(qsTr("Recurring reminder set"), qsTr("Daily reminder activated."))
                        }
                    }
                    MenuItem {
                        text: qsTr("Clear reminder")
                        onTriggered: {
                            backend.clearReminder()
                            backend.sendNotification(qsTr("Reminder cleared"), qsTr("Active reminder removed."))
                        }
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

            UI.StyledButton {
                text: "✕"
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 26
                implicitWidth: 26
                padding: 0
                font.pixelSize: 11
                onClicked: noteWindow.close()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8
        visible: !noteWindow.collapsed

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
            id: contentScroll
            visible: !noteWindow.collapsed
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            TextArea {
                id: contentEditor
                objectName: "contentEditor"
                width: contentScroll.availableWidth
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
    // Frameless window outer border
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: noteWindow.activeBorder
        z: 8
    }

    // Native resize handles for frameless window
    MouseArea {
        id: rightResize
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: 16
        width: 8
        cursorShape: Qt.SizeHorCursor
        z: 10
        onPressed: noteWindow.startSystemResize(Qt.RightEdge)
    }
    MouseArea {
        id: leftResize
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: 16
        width: 8
        cursorShape: Qt.SizeHorCursor
        z: 10
        onPressed: noteWindow.startSystemResize(Qt.LeftEdge)
    }
    MouseArea {
        id: bottomResize
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: 8
        cursorShape: Qt.SizeVerCursor
        z: 10
        onPressed: noteWindow.startSystemResize(Qt.BottomEdge)
    }
    MouseArea {
        id: bottomRightResize
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 16
        height: 16
        cursorShape: Qt.SizeFDiagCursor
        z: 11
        onPressed: noteWindow.startSystemResize(Qt.BottomEdge | Qt.RightEdge)

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 3
            width: 8
            height: 8
            color: "transparent"
            border.width: 1
            border.color: noteWindow.activeBorder
            opacity: 0.5
        }
    }
    MouseArea {
        id: bottomLeftResize
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 16
        height: 16
        cursorShape: Qt.SizeBDiagCursor
        z: 11
        onPressed: noteWindow.startSystemResize(Qt.BottomEdge | Qt.LeftEdge)
    }

    Shortcut { sequences: [StandardKey.Save]; context: Qt.WindowShortcut; onActivated: noteWindow.flush() && noteWindow.persist(true) }
    Shortcut { sequences: [StandardKey.Close]; context: Qt.WindowShortcut; onActivated: noteWindow.close() }
    Shortcut { sequences: [StandardKey.Quit]; context: Qt.WindowShortcut; onActivated: noteWindow.quitRequested() }
}
