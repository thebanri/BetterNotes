pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
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
    readonly property int collapsedHeight: 46

    signal saved()
    signal dismissed(string id)
    signal quitRequested()
    signal libraryRequested()
    signal newNoteRequested()

    property bool alwaysOnTop: false
    property string noteTint: "yellow"
    property string noteFontFamily: "default"
    property int noteFontSize: 13
    property bool isRichText: false

    property bool loadingContent: false
    readonly property bool hasTextSelection: contentEditor.selectionStart !== contentEditor.selectionEnd
    readonly property string plainContent: contentEditor.text.length ? contentEditor.getText(0, contentEditor.length).replace(/[\u2028\u2029]/g, "\n") : ""
    property alias settingsWindow: settingsModal

    // Read the backend only on external changes. A live text binding would feed
    // serialized HTML back into the document and reset selection/undo history.
    function loadContent() {
        if (loadingContent || contentEditor.text === backend.draftContent) return
        loadingContent = true
        isRichText = checkRichText(backend.draftContent)
        contentEditor.textFormat = isRichText ? TextEdit.RichText : TextEdit.PlainText
        contentEditor.text = backend.draftContent
        loadingContent = false
    }

    function ensureRichText() {
        if (isRichText) return
        const start = contentEditor.selectionStart
        const end = contentEditor.selectionEnd
        // Switching textFormat reinterprets its input. Escape plain text once
        // so literal tags, ampersands, whitespace and line breaks survive.
        const plain = contentEditor.getText(0, contentEditor.length)
        const escaped = plain.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const paragraphs = escaped.split("\n").map(function(line) {
            return '<p style="white-space: pre-wrap; margin: 0;">' + (line || "<br>") + '</p>'
        }).join("")
        loadingContent = true
        isRichText = true
        contentEditor.textFormat = TextEdit.RichText
        contentEditor.text = "<html><body>" + paragraphs + "</body></html>"
        loadingContent = false
        contentEditor.select(start, end)
        backend.editContent(contentEditor.text)
        autosave.restart()
    }

    function prepareSelection() {
        if (!hasTextSelection) return false
        ensureRichText()
        contentEditor.forceActiveFocus()
        return true
    }

    function checkRichText(content) {
        if (!content || content.length === 0) return false
        return content.indexOf("<!DOCTYPE") !== -1 ||
               content.indexOf("<html") !== -1 ||
               content.indexOf("<h1") !== -1 ||
               content.indexOf("<h2") !== -1 ||
               content.indexOf("<img") !== -1 ||
               content.indexOf("<font") !== -1 ||
               content.indexOf("<u>") !== -1
    }

    function computeCustomTint(colorHex, role) {
        let base = Qt.color(colorHex)
        if (!base || base === "transparent") return theme.noteBackground
        if (theme.isDark) {
            if (role === "bg") return Qt.rgba(base.r * 0.18 + 0.04, base.g * 0.18 + 0.04, base.b * 0.18 + 0.04, 1.0)
            if (role === "header") return Qt.rgba(base.r * 0.28 + 0.06, base.g * 0.28 + 0.06, base.b * 0.28 + 0.06, 1.0)
            return Qt.rgba(base.r * 0.45 + 0.1, base.g * 0.45 + 0.1, base.b * 0.45 + 0.1, 1.0)
        } else {
            if (role === "bg") return Qt.rgba(1.0 - (1.0 - base.r) * 0.10, 1.0 - (1.0 - base.g) * 0.10, 1.0 - (1.0 - base.b) * 0.10, 1.0)
            if (role === "header") return Qt.rgba(1.0 - (1.0 - base.r) * 0.22, 1.0 - (1.0 - base.g) * 0.22, 1.0 - (1.0 - base.b) * 0.22, 1.0)
            return Qt.rgba(1.0 - (1.0 - base.r) * 0.45, 1.0 - (1.0 - base.g) * 0.45, 1.0 - (1.0 - base.b) * 0.45, 1.0)
        }
    }

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
    readonly property color activeBg: tintPalettes[noteTint] ? tintPalettes[noteTint].bg : (noteTint.startsWith("#") ? computeCustomTint(noteTint, "bg") : theme.noteBackground)
    readonly property color activeHeader: tintPalettes[noteTint] ? tintPalettes[noteTint].header : (noteTint.startsWith("#") ? computeCustomTint(noteTint, "header") : theme.noteHeader)
    readonly property color activeBorder: tintPalettes[noteTint] ? tintPalettes[noteTint].border : (noteTint.startsWith("#") ? computeCustomTint(noteTint, "border") : theme.noteBorder)

    // QObject ownership belongs to the library; these remain independent windows.
    // By default, sticky notes stay on bottom (desktop level) unless toggled to always-on-top.
    // Both stacking hints are X11-only: Wayland has no protocol for a client to
    // place itself in a layer, so on Wayland a note is an ordinary window.
    //
    // Deliberately not Qt.Tool. On X11 Qt makes a tool window without a
    // transient parent transient for the whole application group
    // (WM_TRANSIENT_FOR = client leader), and the window manager then raises
    // every note along with the library whenever the library is activated --
    // straight over other applications, keep-below or not. Hiding notes from
    // the taskbar and switcher is done by the desktop integration instead.
    transientParent: null
    flags: Qt.Window | Qt.FramelessWindowHint | (alwaysOnTop ? Qt.WindowStaysOnTopHint : Qt.WindowStaysOnBottomHint)
    title: (titleEditor.text.trim().length ? titleEditor.text : qsTr("Untitled note")) + " — BetterNotes"
    width: 380
    height: 360
    minimumWidth: 240
    minimumHeight: collapsed ? collapsedHeight : 180
    maximumHeight: collapsed ? collapsedHeight : 16384
    visible: false
    // The surface must stay opaque. A translucent sticky note leaves stale
    // pixels behind on Wayland/KWin every time an interactive resize shrinks it,
    // so a quick drag smears copies of the old frames across the desktop. That
    // rules out window-level rounded corners, which need an alpha channel; the
    // rounded header pill and toolbar carry the soft look instead.
    color: noteWindow.activeBg

    background: Rectangle {
        id: windowCard
        color: noteWindow.activeBg
        border.width: 1
        border.color: noteWindow.activeBorder
    }

    Themes.Theme { id: theme; themeMode: backend.themeMode }
    NotesBackend { id: backend; objectName: "notesBackend" }
    Connections {
        target: backend
        function onDraftContentChanged() { noteWindow.loadContent() }
    }
    ApplicationInfo { id: platformInfo }
    TextFormatter { id: formatter }

    function present(fallbackScreen) {
        if (!backend.initializeNote(noteId)) return false
        collapsed = backend.savedCollapsed()
        const savedColor = backend.noteColor()
        if (savedColor && savedColor.length > 0) noteTint = savedColor
        const savedFont = backend.noteFontFamily()
        if (savedFont && savedFont.length > 0) noteFontFamily = savedFont
        const savedSize = backend.noteFontSize()
        if (savedSize > 0) noteFontSize = savedSize
        loadContent()
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

    // Applies the note's intended layer after the user toggles the pin.
    //
    // Only X11 honours both directions. On Wayland a client cannot restack
    // itself: lower() is a no-op and the stays-on-bottom hint is ignored, so an
    // unpinned note keeps whatever position the compositor gave it. Never call
    // this to "tidy up" a window that is already where the user left it -- on
    // Wayland the raise() half is the only part that takes effect.
    function restoreStacking() {
        if (alwaysOnTop) raise()
        else lower()
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
        settingsModal.close()
        if (!backend.deleteNote()) return false
        retiring = true
        saved()
        close()
        return true
    }

    // Changing the stays-on-top/bottom hint does not restack an already mapped
    // window on its own; nudge it so pinning takes effect immediately. This is
    // an explicit user action, so raising on Wayland is what they asked for.
    onAlwaysOnTopChanged: if (initialized && !retiring) restoreStacking()
    onXChanged: captureGeometry()
    onYChanged: captureGeometry()
    onWidthChanged: captureGeometry()
    onHeightChanged: captureGeometry()
    onScreenChanged: captureGeometry()
    onClosing: function(close) {
        settingsModal.close()
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

    header: Item {
        id: headerContainer
        height: noteWindow.collapsedHeight

        Rectangle {
            id: headerBar
            anchors.fill: parent
            anchors.margins: 5
            color: noteWindow.activeHeader
            radius: height / 2
            antialiasing: true
            border.width: 1
            border.color: noteWindow.activeBorder
        }

        MouseArea {
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.LeftButton
            property point clickPos: Qt.point(0, 0)
            onPressed: function(mouse) {
                clickPos = Qt.point(mouse.x, mouse.y)
            }
            onPositionChanged: function(mouse) {
                if (pressed) {
                    var dx = Math.abs(mouse.x - clickPos.x)
                    var dy = Math.abs(mouse.y - clickPos.y)
                    if (dx > 3 || dy > 3) {
                        noteWindow.startSystemMove()
                    }
                }
            }
            onDoubleClicked: noteWindow.toggleCollapsed()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 3
            z: 1

            UI.StyledButton {
                iconName: "plus"
                iconSize: 14
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 28
                implicitWidth: 28
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: qsTr("New Note")
                onClicked: noteWindow.newNoteRequested()
            }

            UI.StyledButton {
                iconName: noteWindow.collapsed ? "chevron-down" : "chevron-up"
                iconSize: 14
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 28
                implicitWidth: 28
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: noteWindow.collapsed ? qsTr("Expand Note") : qsTr("Collapse Note")
                onClicked: noteWindow.toggleCollapsed()
            }

            UI.StatusBadge {
                visible: noteWindow.width >= 320 && !noteWindow.collapsed
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
                id: pinBtn
                iconName: "pin"
                iconSize: 15
                theme: noteWindow.theme
                variant: noteWindow.alwaysOnTop ? "accent" : "ghost"
                implicitHeight: 28
                implicitWidth: 28
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: noteWindow.alwaysOnTop ? qsTr("Always on Top (Active) — Click to stay on Desktop") : qsTr("On Desktop (Always on Bottom) — Click to Pin on Top")
                ToolTip.delay: 300
                onClicked: {
                    noteWindow.alwaysOnTop = !noteWindow.alwaysOnTop
                }
            }

            UI.StyledButton {
                id: settingsBtn
                iconName: "settings"
                iconSize: 16
                theme: noteWindow.theme
                variant: settingsModal.visible ? "accent" : "ghost"
                implicitHeight: 28
                implicitWidth: 28
                padding: 0
                ToolTip.visible: hovered && !settingsModal.visible
                ToolTip.text: qsTr("Note Settings & Color")
                ToolTip.delay: 300
                onClicked: {
                    settingsModal.openCentered(noteWindow)
                }
            }

            UI.StyledButton {
                iconName: "x"
                iconSize: 14
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 28
                implicitWidth: 28
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Close Note")
                onClicked: noteWindow.close()
            }
        }
    }

    function requestDeleteNote() {
        showDialog(deleteDialog)
    }

    function applyTextColor(colorHex, isDefault) {
        if (!prepareSelection()) return
        formatter.color(contentEditor.textDocument, contentEditor.selectionStart, contentEditor.selectionEnd, colorHex, isDefault)
    }

    function toggleHeading(level) {
        if (!prepareSelection()) return
        // Heading presets apply to precisely the selected text, including a
        // partial line, without replacing paragraphs or adjacent formatting.
        const size = Math.round(noteFontSize * (level === 1 ? 2 : 1.5))
        const active = formatter.sizeActive(contentEditor.textDocument, contentEditor.selectionStart, contentEditor.selectionEnd, size)
        formatter.heading(contentEditor.textDocument, contentEditor.selectionStart, contentEditor.selectionEnd,
            active ? noteFontSize : size, !active)
    }

    function inlineStyleActive(tag) {
        // Reading text makes toolbar state follow format changes as well as selection.
        if (!contentEditor.text.length) return false
        return formatter.styleActive(contentEditor.textDocument, contentEditor.selectionStart, contentEditor.selectionEnd, tag)
    }

    function toggleInlineStyle(tag) {
        if (!prepareSelection()) return
        formatter.toggleStyle(contentEditor.textDocument, contentEditor.selectionStart, contentEditor.selectionEnd, tag)
    }

    function insertImageTag(imageUrl) {
        contentEditor.forceActiveFocus()
        ensureRichText()
        var imgWidth = Math.max(160, Math.min(300, Math.round(contentEditor.width - 24)))
        var imgTag = "<br><img src=\"" + imageUrl + "\" width=\"" + imgWidth + "\" /><br>"
        var pos = contentEditor.cursorPosition
        contentEditor.insert(pos, imgTag)
        backend.editContent(contentEditor.text)
        autosave.restart()
    }

    Shortcut {
        sequence: "Ctrl+B"
        enabled: contentEditor.activeFocus && noteWindow.hasTextSelection
        onActivated: noteWindow.toggleInlineStyle("b")
    }
    Shortcut {
        sequence: "Ctrl+I"
        enabled: contentEditor.activeFocus && noteWindow.hasTextSelection
        onActivated: noteWindow.toggleInlineStyle("i")
    }
    Shortcut {
        sequence: "Ctrl+U"
        enabled: contentEditor.activeFocus && noteWindow.hasTextSelection
        onActivated: noteWindow.toggleInlineStyle("u")
    }
    Shortcut {
        sequence: "Ctrl+1"
        enabled: contentEditor.activeFocus && noteWindow.hasTextSelection
        onActivated: noteWindow.toggleHeading(1)
    }
    Shortcut {
        sequence: "Ctrl+2"
        enabled: contentEditor.activeFocus && noteWindow.hasTextSelection
        onActivated: noteWindow.toggleHeading(2)
    }

    FileDialog {
        id: imageDialog
        title: qsTr("Insert Image or GIF")
        nameFilters: [
            qsTr("Images and GIFs (*.png *.jpg *.jpeg *.gif *.webp *.svg)"),
            qsTr("All files (*)")
        ]
        onAccepted: {
            if (selectedFile) {
                var localUrl = backend.attachImage(selectedFile.toString())
                if (localUrl && localUrl.length > 0) {
                    noteWindow.insertImageTag(localUrl)
                }
            }
        }
    }

    StickyNoteSettingsModal {
        id: settingsModal
        noteWindow: noteWindow
        backend: backend
        theme: noteWindow.theme
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: noteWindow.height < 240 ? 4 : 12
        anchors.bottomMargin: noteWindow.height < 240 ? 6 : 12
        spacing: noteWindow.height < 240 ? 4 : 8
        visible: !noteWindow.collapsed
        clip: true

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
            Layout.preferredHeight: 28
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
                Layout.preferredHeight: 24
                Layout.minimumWidth: 0
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

        // Formatting & Media Toolbar
        Rectangle {
            id: formatToolbar
            objectName: "formatToolbar"
            Layout.fillWidth: true
            Layout.minimumHeight: 32
            Layout.preferredHeight: 32
            radius: height / 2
            color: theme.isDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)
            border.width: 1
            border.color: theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                spacing: 2

                // H1
                UI.StyledButton {
                    objectName: "heading1Button"
                    enabled: noteWindow.hasTextSelection
                    iconName: "heading-1"
                    iconSize: 14
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 24
                    implicitHeight: 24
                    focusPolicy: Qt.NoFocus
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Heading 1 (Ctrl+1)")
                    onClicked: noteWindow.toggleHeading(1)
                }

                // H2
                UI.StyledButton {
                    objectName: "heading2Button"
                    enabled: noteWindow.hasTextSelection
                    iconName: "heading-2"
                    iconSize: 14
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 24
                    implicitHeight: 24
                    focusPolicy: Qt.NoFocus
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Heading 2 (Ctrl+2)")
                    onClicked: noteWindow.toggleHeading(2)
                }

                Rectangle {
                    implicitWidth: 1
                    implicitHeight: 14
                    color: theme.border
                    Layout.alignment: Qt.AlignVCenter
                }

                // Bold
                UI.StyledButton {
                    objectName: "boldButton"
                    enabled: noteWindow.hasTextSelection
                    iconName: "bold"
                    iconSize: 13
                    theme: noteWindow.theme
                    variant: noteWindow.inlineStyleActive("b") ? "accent" : "ghost"
                    implicitWidth: 24
                    implicitHeight: 24
                    focusPolicy: Qt.NoFocus
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Bold (Ctrl+B)")
                    onClicked: noteWindow.toggleInlineStyle("b")
                }

                // Italic
                UI.StyledButton {
                    objectName: "italicButton"
                    enabled: noteWindow.hasTextSelection
                    iconName: "italic"
                    iconSize: 13
                    theme: noteWindow.theme
                    variant: noteWindow.inlineStyleActive("i") ? "accent" : "ghost"
                    implicitWidth: 24
                    implicitHeight: 24
                    focusPolicy: Qt.NoFocus
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Italic (Ctrl+I)")
                    onClicked: noteWindow.toggleInlineStyle("i")
                }

                // Underline
                UI.StyledButton {
                    objectName: "underlineButton"
                    enabled: noteWindow.hasTextSelection
                    iconName: "underline"
                    iconSize: 13
                    theme: noteWindow.theme
                    variant: noteWindow.inlineStyleActive("u") ? "accent" : "ghost"
                    implicitWidth: 24
                    implicitHeight: 24
                    focusPolicy: Qt.NoFocus
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Underline (Ctrl+U)")
                    onClicked: noteWindow.toggleInlineStyle("u")
                }

                Rectangle {
                    implicitWidth: 1
                    implicitHeight: 14
                    color: theme.border
                    Layout.alignment: Qt.AlignVCenter
                }

                // Text Color Dropper
                UI.StyledButton {
                    id: textColorBtn
                    enabled: noteWindow.hasTextSelection
                    iconName: "droplet"
                    iconSize: 13
                    theme: noteWindow.theme
                    variant: textColorPopup.visible ? "accent" : "ghost"
                    implicitWidth: 24
                    implicitHeight: 24
                    focusPolicy: Qt.NoFocus
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered && !textColorPopup.visible
                    ToolTip.text: qsTr("Text Color")
                    onClicked: {
                        textColorPopup.open()
                    }

                    Popup {
                        id: textColorPopup
                        y: textColorBtn.height + 4
                        x: Math.min(0, formatToolbar.width - textColorBtn.x - width)
                        width: 196
                        height: 38
                        padding: 5
                        background: Rectangle {
                            radius: 8
                            color: theme.surfaceElevated
                            border.width: 1
                            border.color: theme.border
                        }

                        RowLayout {
                            anchors.fill: parent
                            spacing: 4

                            Repeater {
                                model: [
                                    { color: theme.noteText, name: qsTr("Default"), isDefault: true },
                                    { color: "#ef4444", name: qsTr("Red"), isDefault: false },
                                    { color: "#f97316", name: qsTr("Orange"), isDefault: false },
                                    { color: "#eab308", name: qsTr("Yellow"), isDefault: false },
                                    { color: "#22c55e", name: qsTr("Green"), isDefault: false },
                                    { color: "#06b6d4", name: qsTr("Cyan"), isDefault: false },
                                    { color: "#6366f1", name: qsTr("Indigo"), isDefault: false },
                                    { color: "#d946ef", name: qsTr("Fuchsia"), isDefault: false }
                                ]

                                delegate: Rectangle {
                                    id: colorSwatch
                                    required property var modelData
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: modelData.color
                                    border.width: modelData.isDefault ? 1.5 : 1
                                    border.color: modelData.isDefault ? noteWindow.theme.border : Qt.darker(modelData.color, 1.2)

                                    ToolTip.visible: colorSwatchArea.containsMouse
                                    ToolTip.text: modelData.name

                                    MouseArea {
                                        id: colorSwatchArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            noteWindow.applyTextColor(colorSwatch.modelData.color, colorSwatch.modelData.isDefault)
                                            textColorPopup.close()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Image / GIF Button
                UI.StyledButton {
                    objectName: "imageButton"
                    iconName: "image"
                    iconSize: 14
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 24
                    implicitHeight: 24
                    focusPolicy: Qt.NoFocus
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Insert Image or GIF")
                    onClicked: imageDialog.open()
                }

                Item { Layout.fillWidth: true }
            }
        }

        ScrollView {
            id: contentScroll
            objectName: "contentScroll"
            contentWidth: availableWidth
            visible: !noteWindow.collapsed
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 24
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            TextArea {
                id: contentEditor
                objectName: "contentEditor"
                width: contentScroll.availableWidth
                textFormat: TextEdit.PlainText
                placeholderText: qsTr("Write your note…")
                Accessible.name: qsTr("Note content")
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                font.family: (noteWindow.noteFontFamily === "default" || noteWindow.noteFontFamily === "") ? "" : noteWindow.noteFontFamily
                font.pixelSize: noteWindow.noteFontSize > 0 ? noteWindow.noteFontSize : 13
                color: theme.noteText
                placeholderTextColor: theme.noteTextSecondary
                selectionColor: theme.accent
                selectedTextColor: theme.accentText
                background: null
                onTextChanged: {
                    if (!noteWindow.loadingContent && text !== backend.draftContent) {
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
    // Native system resize handles for frameless window
    MouseArea {
        id: rightResize
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.bottomMargin: 16
        width: 8
        cursorShape: Qt.SizeHorCursor
        z: 20
        onPressed: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                noteWindow.startSystemResize(Qt.RightEdge)
            }
        }
    }

    MouseArea {
        id: leftResize
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.topMargin: 12
        anchors.bottomMargin: 16
        width: 8
        cursorShape: Qt.SizeHorCursor
        z: 20
        onPressed: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                noteWindow.startSystemResize(Qt.LeftEdge)
            }
        }
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
        z: 20
        enabled: !noteWindow.collapsed
        onPressed: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                noteWindow.startSystemResize(Qt.BottomEdge)
            }
        }
    }

    MouseArea {
        id: bottomRightResize
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 16
        height: 16
        cursorShape: Qt.SizeFDiagCursor
        z: 21
        enabled: !noteWindow.collapsed
        onPressed: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                noteWindow.startSystemResize(Qt.BottomEdge | Qt.RightEdge)
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4
            width: 8
            height: 8
            color: "transparent"
            border.width: 1
            border.color: noteWindow.activeBorder
            opacity: 0.5
            radius: 2
        }
    }

    MouseArea {
        id: bottomLeftResize
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 16
        height: 16
        cursorShape: Qt.SizeBDiagCursor
        z: 21
        enabled: !noteWindow.collapsed
        onPressed: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                noteWindow.startSystemResize(Qt.BottomEdge | Qt.LeftEdge)
            }
        }
    }

    Shortcut { sequences: [StandardKey.Save]; context: Qt.WindowShortcut; onActivated: noteWindow.flush() && noteWindow.persist(true) }
    Shortcut { sequences: [StandardKey.Close]; context: Qt.WindowShortcut; onActivated: noteWindow.close() }
    Shortcut { sequences: [StandardKey.Quit]; context: Qt.WindowShortcut; onActivated: noteWindow.quitRequested() }
}
