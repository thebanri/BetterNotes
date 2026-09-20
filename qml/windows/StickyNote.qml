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
    property bool resizing: false
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
    property string noteFontFamily: "default"
    property int noteFontSize: 13
    property bool isRichText: false

    property int savedSelectionStart: -1
    property int savedSelectionEnd: -1
    property string savedSelectedText: ""

    function updateSavedSelection() {
        if (contentEditor.selectionStart !== contentEditor.selectionEnd) {
            savedSelectionStart = contentEditor.selectionStart
            savedSelectionEnd = contentEditor.selectionEnd
            savedSelectedText = contentEditor.selectedText
        }
    }

    function ensureRichText() {
        if (!isRichText) {
            isRichText = true
            contentEditor.textFormat = TextEdit.RichText
            if (savedSelectionStart !== savedSelectionEnd && savedSelectedText.length > 0) {
                contentEditor.select(savedSelectionStart, savedSelectionEnd)
            }
        }
    }

    function getActiveSelection() {
        var s = contentEditor.selectionStart
        var e = contentEditor.selectionEnd
        var t = contentEditor.selectedText
        if (s === e && savedSelectionStart !== savedSelectionEnd && savedSelectedText.length > 0) {
            s = savedSelectionStart
            e = savedSelectionEnd
            t = savedSelectedText
            contentEditor.select(s, e)
        }
        return {
            start: Math.min(s, e),
            end: Math.max(s, e),
            text: t,
            hasSelection: (s !== e && t.length > 0)
        }
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
    // Qt.Tool ensures desktop sticky notes act as utility widgets and do not appear as separate application windows in the taskbar/dock.
    // By default, sticky notes stay on bottom (desktop level) unless toggled to always-on-top.
    transientParent: null
    flags: Qt.Tool | Qt.FramelessWindowHint | (alwaysOnTop ? Qt.WindowStaysOnTopHint : Qt.WindowStaysOnBottomHint)
    title: (titleEditor.text.trim().length ? titleEditor.text : qsTr("Untitled note")) + " — BetterNotes"
    width: 380
    height: 360
    minimumWidth: 240
    minimumHeight: collapsed ? collapsedHeight : 180
    maximumHeight: collapsed ? collapsedHeight : 16384
    visible: false
    color: noteWindow.activeBg

    background: Rectangle {
        id: windowCard
        color: noteWindow.activeBg
        border.width: 1
        border.color: noteWindow.activeBorder
    }

    Themes.Theme { id: theme; themeMode: backend.themeMode }
    NotesBackend { id: backend; objectName: "notesBackend" }
    ApplicationInfo { id: platformInfo }

    function present(fallbackScreen) {
        if (!backend.initializeNote(noteId)) return false
        collapsed = backend.savedCollapsed()
        const savedColor = backend.noteColor()
        if (savedColor && savedColor.length > 0) noteTint = savedColor
        const savedFont = backend.noteFontFamily()
        if (savedFont && savedFont.length > 0) noteFontFamily = savedFont
        const savedSize = backend.noteFontSize()
        if (savedSize > 0) noteFontSize = savedSize
        isRichText = checkRichText(backend.draftContent)
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
        if (!initialized || placing || retiring || resizing || visibility !== Window.Windowed) return
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

    header: Rectangle {
        id: headerContainer
        height: 38
        color: noteWindow.activeBg

        Rectangle {
            id: headerBar
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            anchors.topMargin: 3
            anchors.bottomMargin: 3
            color: activeHeader
            radius: 8
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
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 6
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
        contentEditor.forceActiveFocus()
        ensureRichText()
        var sel = getActiveSelection()
        if (sel.hasSelection) {
            contentEditor.remove(sel.start, sel.end)
            if (isDefault) {
                contentEditor.insert(sel.start, sel.text)
            } else {
                contentEditor.insert(sel.start, "<font color='" + colorHex + "'>" + sel.text + "</font>")
            }
            contentEditor.select(sel.start, sel.start + sel.text.length)
            savedSelectionStart = sel.start
            savedSelectionEnd = sel.start + sel.text.length
            savedSelectedText = sel.text
        } else {
            var pos = contentEditor.cursorPosition
            var word = qsTr("text")
            if (isDefault) {
                contentEditor.insert(pos, word)
            } else {
                contentEditor.insert(pos, "<font color='" + colorHex + "'>" + word + "</font>")
            }
            contentEditor.select(pos, pos + word.length)
        }
        backend.editContent(contentEditor.text)
        autosave.restart()
    }

    function toggleHeading(level) {
        contentEditor.forceActiveFocus()
        ensureRichText()
        var sel = getActiveSelection()
        var s = sel.start
        var e = sel.end

        var plain = contentEditor.getText(0, contentEditor.length)
        var paragraphs = plain.split(/\u2029|\r?\n/)
        var charCount = 0
        var startBlock = -1
        var endBlock = -1

        for (var i = 0; i < paragraphs.length; i++) {
            var pLen = paragraphs[i].length
            var pEnd = charCount + pLen
            charCount += pLen + 1

            if (startBlock === -1 && s <= pEnd) {
                startBlock = i
            }
            if (e <= pEnd || i === paragraphs.length - 1) {
                endBlock = i
                break
            }
        }
        if (startBlock === -1) startBlock = 0
        if (endBlock === -1) endBlock = startBlock

        var html = contentEditor.text
        var bodyStart = html.indexOf("<body")
        if (bodyStart === -1) return
        var bodyTagEnd = html.indexOf(">", bodyStart) + 1
        var bodyEnd = html.indexOf("</body>", bodyTagEnd)
        if (bodyEnd === -1) return

        var header = html.substring(0, bodyTagEnd)
        var body = html.substring(bodyTagEnd, bodyEnd)
        var footer = html.substring(bodyEnd)

        var blockRegex = /<(p|h1|h2)[^>]*>([\s\S]*?)<\/\1>/gi
        var blocks = []
        var match
        while ((match = blockRegex.exec(body)) !== null) {
            blocks.push({
                full: match[0],
                tag: match[1].toLowerCase(),
                content: match[2]
            })
        }

        var allSame = true
        var targetTag = "h" + level
        for (var b = startBlock; b <= endBlock && b < blocks.length; b++) {
            if (blocks[b].tag !== targetTag) {
                allSame = false
                break
            }
        }

        var newTag = allSame ? "p" : targetTag

        var newBody = ""
        var lastIdx = 0
        blockRegex.lastIndex = 0
        var bIdx = 0

        while ((match = blockRegex.exec(body)) !== null) {
            newBody += body.substring(lastIdx, match.index)
            if (bIdx >= startBlock && bIdx <= endBlock) {
                var content = match[2]
                content = content.replace(/font-size:(xx-large|x-large);/gi, "")
                content = content.replace(/font-weight:700;/gi, "")

                if (newTag === "h1") {
                    newBody += "<h1 style=' margin-top:18px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;'><span style=' font-size:xx-large; font-weight:700;'>" + content + "</span></h1>"
                } else if (newTag === "h2") {
                    newBody += "<h2 style=' margin-top:16px; margin-bottom:10px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;'><span style=' font-size:x-large; font-weight:700;'>" + content + "</span></h2>"
                } else {
                    newBody += "<p style=' margin-top:12px; margin-bottom:12px; margin-left:0px; margin-right:0px; -qt-block-indent:0; text-indent:0px;'>" + content + "</p>"
                }
            } else {
                newBody += match[0]
            }
            lastIdx = blockRegex.lastIndex
            bIdx++
        }
        newBody += body.substring(lastIdx)

        contentEditor.text = header + newBody + footer
        contentEditor.select(s, e)
        savedSelectionStart = s
        savedSelectionEnd = e
        savedSelectedText = sel.text
        backend.editContent(contentEditor.text)
        autosave.restart()
    }

    function isStyleActive(tag, text) {
        var html = contentEditor.text
        var escaped = text.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&')
        if (tag === "b") {
            var boldRegex = new RegExp("<(b|strong)>[^<]*" + escaped + "[^<]*<\\/\\1>|<span[^>]*font-weight:700[^>]*>[^<]*" + escaped + "[^<]*<\\/span>", "i")
            return boldRegex.test(html)
        }
        if (tag === "i") {
            var italicRegex = new RegExp("<(i|em)>[^<]*" + escaped + "[^<]*<\\/\\1>|<span[^>]*font-style:italic[^>]*>[^<]*" + escaped + "[^<]*<\\/span>", "i")
            return italicRegex.test(html)
        }
        if (tag === "u") {
            var underlineRegex = new RegExp("<u>[^<]*" + escaped + "[^<]*<\\/u>|<span[^>]*text-decoration: underline[^>]*>[^<]*" + escaped + "[^<]*<\\/span>", "i")
            return underlineRegex.test(html)
        }
        return false
    }

    function toggleInlineStyle(tag) {
        contentEditor.forceActiveFocus()
        ensureRichText()
        var sel = getActiveSelection()
        if (sel.hasSelection) {
            var s = sel.start
            var e = sel.end
            var text = sel.text
            var active = isStyleActive(tag, text)
            contentEditor.remove(s, e)
            if (active) {
                contentEditor.insert(s, text)
            } else {
                contentEditor.insert(s, "<" + tag + ">" + text + "</" + tag + ">")
            }
            contentEditor.select(s, s + text.length)
            savedSelectionStart = s
            savedSelectionEnd = s + text.length
            savedSelectedText = text
        } else {
            var pos = contentEditor.cursorPosition
            var word = qsTr("text")
            contentEditor.insert(pos, "<" + tag + ">" + word + "</" + tag + ">")
            contentEditor.select(pos, pos + word.length)
        }
        backend.editContent(contentEditor.text)
        autosave.restart()
    }

    function formatSelection(prefix, suffix) {
        contentEditor.forceActiveFocus()
        ensureRichText()
        var sel = getActiveSelection()
        if (sel.hasSelection) {
            contentEditor.remove(sel.start, sel.end)
            contentEditor.insert(sel.start, prefix + sel.text + suffix)
            contentEditor.select(sel.start, sel.start + sel.text.length)
            savedSelectionStart = sel.start
            savedSelectionEnd = sel.start + sel.text.length
            savedSelectedText = sel.text
        } else {
            var pos = contentEditor.cursorPosition
            contentEditor.insert(pos, prefix + qsTr("text") + suffix)
        }
        backend.editContent(contentEditor.text)
        autosave.restart()
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
        onActivated: noteWindow.toggleInlineStyle("b")
    }
    Shortcut {
        sequence: "Ctrl+I"
        onActivated: noteWindow.toggleInlineStyle("i")
    }
    Shortcut {
        sequence: "Ctrl+U"
        onActivated: noteWindow.toggleInlineStyle("u")
    }
    Shortcut {
        sequence: "Ctrl+1"
        onActivated: noteWindow.toggleHeading(1)
    }
    Shortcut {
        sequence: "Ctrl+2"
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
        anchors.margins: 10
        spacing: 8
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

        // Formatting & Media Toolbar
        Rectangle {
            id: formatToolbar
            Layout.fillWidth: true
            height: 28
            radius: 6
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
                    iconName: "heading-1"
                    iconSize: 14
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 26
                    implicitHeight: 24
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
                    iconName: "heading-2"
                    iconSize: 14
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 26
                    implicitHeight: 24
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Heading 2 (Ctrl+2)")
                    onClicked: noteWindow.toggleHeading(2)
                }

                Rectangle {
                    width: 1
                    height: 14
                    color: theme.border
                    Layout.alignment: Qt.AlignVCenter
                }

                // Bold
                UI.StyledButton {
                    iconName: "bold"
                    iconSize: 13
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 26
                    implicitHeight: 24
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
                    iconName: "italic"
                    iconSize: 13
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 26
                    implicitHeight: 24
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
                    iconName: "underline"
                    iconSize: 13
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 26
                    implicitHeight: 24
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Underline (Ctrl+U)")
                    onClicked: noteWindow.toggleInlineStyle("u")
                }

                Rectangle {
                    width: 1
                    height: 14
                    color: theme.border
                    Layout.alignment: Qt.AlignVCenter
                }

                // Text Color Dropper
                UI.StyledButton {
                    id: textColorBtn
                    iconName: "droplet"
                    iconSize: 13
                    theme: noteWindow.theme
                    variant: textColorPopup.visible ? "accent" : "ghost"
                    implicitWidth: 26
                    implicitHeight: 24
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    Layout.alignment: Qt.AlignVCenter
                    ToolTip.visible: hovered && !textColorPopup.visible
                    ToolTip.text: qsTr("Text Color")
                    onClicked: {
                        noteWindow.updateSavedSelection()
                        textColorPopup.open()
                    }

                    Popup {
                        id: textColorPopup
                        y: textColorBtn.height + 4
                        x: -4
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
                                    border.color: modelData.isDefault ? theme.border : Qt.darker(modelData.color, 1.2)

                                    ToolTip.visible: colorSwatchArea.containsMouse
                                    ToolTip.text: modelData.name

                                    MouseArea {
                                        id: colorSwatchArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            noteWindow.applyTextColor(modelData.color, modelData.isDefault)
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
                    iconName: "image"
                    iconSize: 14
                    theme: noteWindow.theme
                    variant: "ghost"
                    implicitWidth: 26
                    implicitHeight: 24
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
            visible: !noteWindow.collapsed
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            TextArea {
                id: contentEditor
                objectName: "contentEditor"
                width: Math.max(100, contentScroll.availableWidth)
                text: backend.draftContent
                textFormat: noteWindow.isRichText ? TextEdit.RichText : TextEdit.PlainText
                placeholderText: qsTr("Write your note…")
                Accessible.name: qsTr("Note content")
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                font.family: (noteFontFamily === "default" || noteFontFamily === "") ? "" : noteFontFamily
                font.pixelSize: noteFontSize > 0 ? noteFontSize : 13
                color: theme.noteText
                placeholderTextColor: theme.noteTextSecondary
                selectionColor: theme.accent
                selectedTextColor: theme.accentText
                background: null
                onSelectionStartChanged: noteWindow.updateSavedSelection()
                onSelectionEndChanged: noteWindow.updateSavedSelection()
                onSelectedTextChanged: noteWindow.updateSavedSelection()
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
