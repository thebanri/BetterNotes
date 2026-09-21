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
    property alias imageAnimator: gifs
    property alias imageFormatter: formatter
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
    // Emitted for every clicked link, before deciding whether it may open.
    signal linkClicked(string link)

    property bool alwaysOnTop: false
    // Library-wide preference: unpinned notes stay beneath ordinary windows.
    property bool stayBelow: true
    // Invisible caption suffix naming this note's layer. Wayland gives a client
    // no way to set its own layer, so on KDE Plasma the desktop integration's
    // KWin script reads it from the caption and applies keep-below/keep-above.
    // Must match the markers in crates/core/src/desktop.rs.
    readonly property string layerMarker: alwaysOnTop ? "\u2064" : (stayBelow ? "\u2063" : "")
    // Invisible caption key naming this note (its id as Unicode tag digits,
    // U+E0030..U+E0039). The KWin script uses it to ask WindowPlacement where
    // the note belongs, since Wayland lets no client position its own windows.
    readonly property string noteKeyMarker: noteId.split("").map(function(digit) {
        return String.fromCodePoint(0xE0030 + Number(digit))
    }).join("")
    // Shared WindowPlacement service from the library; null in tests.
    property var placement: null
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
        selectedImage = -1
        gifs.refresh()
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

    readonly property color activeBg: theme.noteTint(noteTint, "bg")
    readonly property color activeHeader: theme.noteTint(noteTint, "header")
    readonly property color activeBorder: theme.noteTint(noteTint, "border")

    // QObject ownership belongs to the library; these remain independent windows.
    // Unpinned notes stay on bottom (desktop level) while stayBelow is set;
    // pinned notes stay on top. The window hints below only work on X11:
    // Wayland has no protocol for a client to place itself in a layer. There,
    // KDE Plasma applies the layer from layerMarker; other Wayland desktops
    // treat a note as an ordinary window.
    //
    // Deliberately not Qt.Tool. On X11 Qt makes a tool window without a
    // transient parent transient for the whole application group
    // (WM_TRANSIENT_FOR = client leader), and the window manager then raises
    // every note along with the library whenever the library is activated --
    // straight over other applications, keep-below or not. Hiding notes from
    // the taskbar and switcher is done by the desktop integration instead.
    transientParent: null
    flags: Qt.Window | Qt.FramelessWindowHint
        | (alwaysOnTop ? Qt.WindowStaysOnTopHint : (stayBelow ? Qt.WindowStaysOnBottomHint : 0))
    title: (titleEditor.text.trim().length ? titleEditor.text : qsTr("Untitled note")) + " — BetterNotes" + layerMarker + noteKeyMarker
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
    // GIFs play only while someone can see them.
    ImageAnimator {
        id: gifs
        document: contentEditor.textDocument
        running: noteWindow.visible && !noteWindow.collapsed
            && noteWindow.visibility !== Window.Minimized
    }

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
        // Register before the window appears: the window manager asks for the
        // saved position as soon as it maps the window.
        if (placement) placement.track(noteId, backend.savedPositioned(), backend.savedX(), backend.savedY())
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
        if (canPosition) {
            normalX = (x !== 0 || y !== 0) ? x : (state.x || fitted.x)
            normalY = (x !== 0 || y !== 0) ? y : (state.y || fitted.y)
        } else {
            // Where the window really is comes only from the window manager
            // (WindowPlacement); a computed default must not be saved as if
            // the user had put the note there.
            normalX = state.positioned ? state.x : 0
            normalY = state.positioned ? state.y : 0
        }
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
        else if (stayBelow) lower()
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
        // On Wayland x and y are not the window's position, so they must not
        // overwrite one reported by the window manager.
        if (canPosition && (x !== 0 || y !== 0)) {
            normalX = x
            normalY = y
        }
        normalScreen = screen ? screen.name : ""
        geometrySave.restart()
    }

    // The window manager reports where the note is (see WindowPlacement).
    function moveReported(reportedX, reportedY) {
        normalX = reportedX
        normalY = reportedY
        if (initialized && !retiring) persist(true)
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
    // Links are formatted a moment after typing pauses, not on every keystroke.
    Timer {
        id: linkScan
        interval: 350
        onTriggered: {
            noteWindow.linkifyContent()
            gifs.refresh()
        }
    }
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

    // Formats web addresses in the note as links. Links need character formats,
    // so a plain-text note that gains an address becomes rich text first.
    function linkifyContent() {
        if (loadingContent || collapsed) return
        if (!isRichText) {
            if (!formatter.containsLink(plainContent)) return
            ensureRichText()
        }
        if (formatter.linkify(contentEditor.textDocument, theme.link) > 0) {
            backend.editContent(contentEditor.text)
            autosave.restart()
        }
    }

    // The link under a point in the editor's own coordinates, or "".
    //
    // Not TextEdit.linkAt(): in this editor it answers about 16px up and to the
    // left of where the text is drawn. positionAt()/positionToRectangle() map
    // correctly, but positionAt() snaps to the nearest caret position, so check
    // that the point really lies on the character before or after it --
    // otherwise clicking past the end of a line would open a link at its end.
    function characterAt(x, y) {
        const position = contentEditor.positionAt(x, y)
        for (const character of [position - 1, position]) {
            if (character < 0 || character >= contentEditor.length) continue
            const from = contentEditor.positionToRectangle(character)
            const to = contentEditor.positionToRectangle(character + 1)
            if (from.y !== to.y) continue // the character ends a wrapped line
            if (x >= Math.min(from.x, to.x) && x < Math.max(from.x, to.x)
                    && y >= from.y && y < from.y + from.height)
                return character
        }
        return -1
    }

    function linkAt(x, y) {
        const character = characterAt(x, y)
        return character < 0 ? "" : formatter.anchorAt(contentEditor.textDocument, character)
    }

    // ---- Images -----------------------------------------------------------

    // Document position of the image selected for resizing, or -1.
    property int selectedImage: -1
    property rect selectedImageRect: Qt.rect(0, 0, 0, 0)
    readonly property int maxImageWidth: Math.max(48, Math.round(contentEditor.width - 8))
    readonly property var imageSuffixes: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"]

    function isImageUrl(url) {
        const path = url.toString().split(/[?#]/)[0].toLowerCase()
        if (!path.startsWith("file:")) return false
        return imageSuffixes.indexOf(path.substring(path.lastIndexOf(".") + 1)) >= 0
    }

    // Selects the image under a point so it can be resized or deleted.
    function selectImageAt(x, y) {
        const character = characterAt(x, y)
        if (character < 0 || !formatter.imageAt(contentEditor.textDocument, character).name) return false
        contentEditor.select(character, character + 1)
        selectedImage = character
        updateImageSelection()
        return true
    }

    function updateImageSelection() {
        if (selectedImage < 0) return
        const image = formatter.imageAt(contentEditor.textDocument, selectedImage)
        if (!image.name) {
            selectedImage = -1
            return
        }
        const start = contentEditor.positionToRectangle(selectedImage)
        selectedImageRect = Qt.rect(start.x, start.y, image.width, image.height)
    }

    function resizeSelectedImage(width) {
        if (selectedImage < 0) return
        const clamped = Math.max(24, Math.min(maxImageWidth, Math.round(width)))
        if (formatter.resizeImage(contentEditor.textDocument, selectedImage, clamped)) {
            contentEditor.select(selectedImage, selectedImage + 1)
            updateImageSelection()
        }
    }

    // Copies each image into the note's attachments and inserts it at the
    // position, each on its own line, at most as wide as the note.
    function insertImages(urls, position) {
        let inserted = 0
        for (let i = 0; i < urls.length; ++i) {
            const url = urls[i].toString()
            if (!isImageUrl(url)) continue
            const width = formatter.fittedImageWidth(url, maxImageWidth)
            if (width <= 0) continue
            const stored = backend.attachImage(url)
            if (!stored || stored.length === 0) continue
            ensureRichText()
            const at = Math.max(0, Math.min(position, contentEditor.length))
            const lineStart = at === 0 || contentEditor.getText(at - 1, at) === "\n"
                || contentEditor.getText(at - 1, at) === "\u2029"
            const tag = (lineStart ? "" : "<br>") + "<img src=\"" + stored + "\" width=\"" + width + "\" /><br>"
            const before = contentEditor.length
            contentEditor.insert(at, tag)
            position = at + (contentEditor.length - before)
            ++inserted
        }
        if (inserted === 0) return 0
        contentEditor.forceActiveFocus()
        contentEditor.cursorPosition = Math.min(position, contentEditor.length)
        backend.editContent(contentEditor.text)
        autosave.restart()
        gifs.refresh()
        return inserted
    }

    // ---- Lists ------------------------------------------------------------

    // Typing "- ", "* ", ". " or "1. " at the start of a line starts a list.
    function continueList() {
        const position = contentEditor.cursorPosition
        if (position < 2 || contentEditor.getText(position - 1, position) !== " ") return
        if (!isRichText) {
            if (!formatter.startsList(plainContent, position)) return
            ensureRichText()
        }
        const caret = formatter.autoList(contentEditor.textDocument, contentEditor.cursorPosition)
        if (caret < 0) return
        contentEditor.cursorPosition = caret
        backend.editContent(contentEditor.text)
        autosave.restart()
    }

    // ---- Tags -------------------------------------------------------------

    function addTags(text) {
        const tags = []
        for (let i = 0; i < backend.tags.length; ++i) tags.push(backend.tags[i])
        const lower = tags.map(function(tag) { return tag.toLowerCase() })
        let changed = false
        for (let part of text.split(",")) {
            part = part.trim().replace(/^#+/, "").trim()
            if (part.length === 0 || lower.indexOf(part.toLowerCase()) >= 0) continue
            tags.push(part)
            lower.push(part.toLowerCase())
            changed = true
        }
        if (!changed) return
        backend.setTags(tags.join(", "))
        autosave.restart()
    }

    function removeTag(index) {
        const tags = []
        for (let i = 0; i < backend.tags.length; ++i) if (i !== index) tags.push(backend.tags[i])
        backend.setTags(tags.join(", "))
        autosave.restart()
    }

    // Opens a clicked link in the desktop's browser or mail client. Note
    // content is untrusted, so the core decides which links may open at all.
    function openLink(link) {
        linkClicked(link)
        const url = platformInfo.externalUrl(link)
        if (url.length > 0) Qt.openUrlExternally(url)
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
        title: qsTr("Insert Images or GIFs")
        fileMode: FileDialog.OpenFiles
        currentFolder: backend.picturesFolder()
        nameFilters: [
            qsTr("Images and GIFs (*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg)"),
            qsTr("Animated GIFs (*.gif)")
        ]
        onAccepted: {
            const urls = []
            for (let i = 0; i < selectedFiles.length; ++i) urls.push(selectedFiles[i])
            if (urls.length > 0) currentFolder = urls[0].toString().replace(/\/[^\/]*$/, "")
            noteWindow.insertImages(urls, contentEditor.cursorPosition)
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

            // Tags as removable chips; typing a tag and pressing Enter (or a
            // comma) adds it, Backspace in the empty field removes the last.
            Flow {
                id: tagFlow
                objectName: "tagFlow"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredHeight: implicitHeight
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                Repeater {
                    model: backend.tags
                    delegate: Rectangle {
                        id: chip
                        required property string modelData
                        required property int index
                        height: 22
                        width: Math.min(chipRow.implicitWidth + 12, tagFlow.width)
                        radius: height / 2
                        color: theme.isDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.07)
                        border.width: 1
                        border.color: theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)

                        RowLayout {
                            id: chipRow
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 4
                            spacing: 2
                            Label {
                                text: "#" + chip.modelData
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: theme.noteText
                                Layout.fillWidth: true
                                Layout.maximumWidth: tagFlow.width - 34
                            }
                            Rectangle {
                                implicitWidth: 16
                                implicitHeight: 16
                                radius: 8
                                color: removeArea.containsMouse ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.1)) : "transparent"
                                UI.AppIcon {
                                    anchors.centerIn: parent
                                    name: "x"
                                    size: 10
                                    color: theme.noteTextSecondary
                                }
                                MouseArea {
                                    id: removeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    Accessible.role: Accessible.Button
                                    Accessible.name: qsTr("Remove tag %1").arg(chip.modelData)
                                    onClicked: noteWindow.removeTag(chip.index)
                                }
                            }
                        }
                    }
                }

                TextField {
                    id: tagsEditor
                    objectName: "tagInput"
                    height: 22
                    width: Math.min(tagFlow.width, Math.max(90, contentWidth + leftPadding + rightPadding + 8))
                    topPadding: 2
                    bottomPadding: 2
                    leftPadding: 6
                    rightPadding: 6
                    placeholderText: backend.tags.length > 0 ? qsTr("Add tag") : qsTr("Add tags, press Enter")
                    Accessible.name: qsTr("Add a tag")
                    selectByMouse: true
                    font.pixelSize: 11
                    color: theme.noteText
                    placeholderTextColor: theme.noteTextSecondary
                    background: Rectangle {
                        color: "transparent"
                        radius: height / 2
                        border.width: tagsEditor.activeFocus ? 1 : 0
                        border.color: theme.border
                    }
                    onTextEdited: {
                        if (text.indexOf(",") >= 0) {
                            noteWindow.addTags(text)
                            text = ""
                        }
                    }
                    onAccepted: {
                        noteWindow.addTags(text)
                        text = ""
                    }
                    onEditingFinished: {
                        if (text.trim().length > 0) {
                            noteWindow.addTags(text)
                            text = ""
                        }
                    }
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Backspace && text.length === 0 && backend.tags.length > 0) {
                            noteWindow.removeTag(backend.tags.length - 1)
                            event.accepted = true
                        }
                    }
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
                Layout.alignment: Qt.AlignTop
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
                    ToolTip.text: qsTr("Insert images or GIFs — or drop them onto the note")
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
                // A selected image keeps its own colors under a light tint.
                selectionColor: noteWindow.selectedImage >= 0
                    ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : theme.accent
                selectedTextColor: theme.accentText
                background: null
                onTextChanged: {
                    // A GIF frame redraws the document without editing it.
                    if (gifs.updating || noteWindow.loadingContent) return
                    if (text !== backend.draftContent) {
                        backend.editContent(text)
                        autosave.restart()
                        linkScan.restart()
                        // The caret moves past typed text after this signal.
                        Qt.callLater(noteWindow.continueList)
                    }
                    noteWindow.updateImageSelection()
                }
                onWidthChanged: noteWindow.updateImageSelection()
                // Any other selection ends image resizing.
                onSelectionStartChanged: if (noteWindow.selectedImage >= 0 && selectionStart !== noteWindow.selectedImage) noteWindow.selectedImage = -1
                onSelectionEndChanged: if (noteWindow.selectedImage >= 0 && selectionEnd !== noteWindow.selectedImage + 1) noteWindow.selectedImage = -1

                // Enter on an empty list item ends the list.
                Keys.onReturnPressed: function(event) {
                    event.accepted = noteWindow.isRichText && event.modifiers === Qt.NoModifier
                        && formatter.endEmptyListItem(contentEditor.textDocument, contentEditor.cursorPosition)
                }
                Keys.onEscapePressed: function(event) {
                    event.accepted = noteWindow.selectedImage >= 0
                    if (event.accepted) contentEditor.deselect()
                }

                // A plain click on a link opens it and a click on an image
                // selects it for resizing; anywhere else the click places the
                // caret as usual.
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: function(eventPoint) {
                        const link = noteWindow.linkAt(eventPoint.position.x, eventPoint.position.y)
                        if (link.length > 0) noteWindow.openLink(link)
                        else noteWindow.selectImageAt(eventPoint.position.x, eventPoint.position.y)
                    }
                }

                // Frame and corner handle of the selected image. Dragging the
                // handle resizes the image, keeping its aspect ratio.
                Item {
                    id: imageFrame
                    objectName: "imageFrame"
                    visible: noteWindow.selectedImage >= 0
                    x: noteWindow.selectedImageRect.x
                    y: noteWindow.selectedImageRect.y
                    width: noteWindow.selectedImageRect.width
                    height: noteWindow.selectedImageRect.height
                    z: 5

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.width: 2
                        border.color: theme.accent
                        radius: 2
                    }

                    Rectangle {
                        visible: resizeHandle.pressed
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 6
                        width: sizeLabel.implicitWidth + 12
                        height: sizeLabel.implicitHeight + 6
                        radius: height / 2
                        color: Qt.rgba(0, 0, 0, 0.65)
                        Label {
                            id: sizeLabel
                            anchors.centerIn: parent
                            text: qsTr("%1 × %2").arg(Math.round(imageFrame.width)).arg(Math.round(imageFrame.height))
                            color: "white"
                            font.pixelSize: 11
                        }
                    }

                    Rectangle {
                        id: handleDot
                        width: 14
                        height: 14
                        radius: 7
                        x: parent.width - width / 2 - 1
                        y: parent.height - height / 2 - 1
                        color: theme.accent
                        border.width: 2
                        border.color: "white"

                        MouseArea {
                            id: resizeHandle
                            objectName: "imageResizeHandle"
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.SizeFDiagCursor
                            preventStealing: true
                            property real startX: 0
                            property real startWidth: 0
                            onPressed: function(mouse) {
                                startX = mapToItem(null, mouse.x, mouse.y).x
                                startWidth = imageFrame.width
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed) return
                                const dx = mapToItem(null, mouse.x, mouse.y).x - startX
                                noteWindow.resizeSelectedImage(startWidth + dx)
                            }
                        }
                    }
                }
                HoverHandler {
                    id: linkHover
                    cursorShape: noteWindow.linkAt(linkHover.point.position.x, linkHover.point.position.y).length > 0
                        ? Qt.PointingHandCursor : Qt.IBeamCursor
                }
            }
        }
    }

    // Images and GIFs dragged from a file manager are added where they are
    // dropped, or at the end when dropped outside the text.
    DropArea {
        id: imageDrop
        objectName: "imageDrop"
        anchors.fill: parent
        enabled: !noteWindow.collapsed
        z: 30
        property bool acceptable: false
        onEntered: function(drag) {
            acceptable = drag.hasUrls && drag.urls.some(function(url) { return noteWindow.isImageUrl(url) })
            drag.accepted = acceptable
            if (acceptable) drag.acceptProposedAction()
        }
        onExited: acceptable = false
        onDropped: function(drop) {
            acceptable = false
            const point = imageDrop.mapToItem(contentEditor, drop.x, drop.y)
            const inside = point.x >= 0 && point.y >= 0 && point.x <= contentEditor.width && point.y <= contentEditor.height
            const position = inside ? contentEditor.positionAt(point.x, point.y) : contentEditor.length
            if (noteWindow.insertImages(drop.urls, position) > 0) drop.acceptProposedAction()
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            visible: imageDrop.containsDrag && imageDrop.acceptable
            color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.08)
            border.width: 2
            border.color: theme.accent
            radius: 8
            Label {
                anchors.centerIn: parent
                text: qsTr("Drop to add to the note")
                color: theme.noteText
                font.pixelSize: 13
                font.weight: Font.DemiBold
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
