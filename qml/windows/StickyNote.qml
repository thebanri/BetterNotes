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
    color: activeBg

    background: Rectangle {
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

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: noteWindow.activeBorder
        }

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
                id: pinBtn
                theme: noteWindow.theme
                variant: noteWindow.alwaysOnTop ? "accent" : "ghost"
                implicitHeight: 28
                implicitWidth: 28
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: noteWindow.alwaysOnTop ? qsTr("Always on Top (Active)") : qsTr("On Desktop (Always on Bottom)")
                ToolTip.delay: 400
                onClicked: {
                    noteWindow.alwaysOnTop = !noteWindow.alwaysOnTop
                }

                contentItem: Canvas {
                    id: pinCanvas
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    renderTarget: Canvas.FramebufferObject
                    property color iconColor: noteWindow.alwaysOnTop ? theme.accentText : (pinBtn.hovered ? theme.textPrimary : theme.textSecondary)
                    property bool active: noteWindow.alwaysOnTop

                    onIconColorChanged: requestPaint()
                    onActiveChanged: requestPaint()
                    Connections {
                        target: noteWindow
                        function onAlwaysOnTopChanged() { pinCanvas.requestPaint() }
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = iconColor
                        ctx.strokeStyle = iconColor
                        ctx.lineWidth = 1.6
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"

                        // Top bar
                        ctx.beginPath()
                        ctx.moveTo(4, 3)
                        ctx.lineTo(12, 3)
                        ctx.stroke()

                        // Pin head
                        ctx.beginPath()
                        ctx.moveTo(5, 3)
                        ctx.lineTo(6, 8)
                        ctx.lineTo(10, 8)
                        ctx.lineTo(11, 3)
                        ctx.closePath()
                        if (active) ctx.fill()
                        else ctx.stroke()

                        // Ridge
                        ctx.beginPath()
                        ctx.moveTo(3, 8)
                        ctx.lineTo(13, 8)
                        ctx.stroke()

                        // Needle
                        ctx.beginPath()
                        ctx.moveTo(8, 8)
                        ctx.lineTo(8, 14)
                        ctx.stroke()
                    }
                }
            }

            UI.StyledButton {
                id: settingsBtn
                theme: noteWindow.theme
                variant: noteSettingsPopup.visible ? "accent" : "ghost"
                implicitHeight: 28
                implicitWidth: 28
                padding: 0
                ToolTip.visible: hovered && !noteSettingsPopup.visible
                ToolTip.text: qsTr("Note Settings & Color")
                ToolTip.delay: 400
                onClicked: {
                    if (noteWindow.collapsed) noteWindow.toggleCollapsed()
                    if (noteSettingsPopup.visible) noteSettingsPopup.close()
                    else noteSettingsPopup.open()
                }

                contentItem: Canvas {
                    id: settingsCanvas
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    renderTarget: Canvas.FramebufferObject
                    property color iconColor: noteSettingsPopup.visible ? theme.accentText : (settingsBtn.hovered ? theme.textPrimary : theme.textSecondary)

                    onIconColorChanged: requestPaint()
                    Connections {
                        target: noteSettingsPopup
                        function onVisibleChanged() { settingsCanvas.requestPaint() }
                    }

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = iconColor
                        ctx.strokeStyle = iconColor
                        ctx.lineWidth = 2.0
                        ctx.lineCap = "round"

                        // Top slider track + knob
                        ctx.beginPath()
                        ctx.moveTo(2, 5.5)
                        ctx.lineTo(16, 5.5)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.arc(6, 5.5, 3.0, 0, 2 * Math.PI)
                        ctx.fill()

                        // Bottom slider track + knob
                        ctx.beginPath()
                        ctx.moveTo(2, 12.5)
                        ctx.lineTo(16, 12.5)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.arc(12, 12.5, 3.0, 0, 2 * Math.PI)
                        ctx.fill()
                    }
                }
            }

            UI.StyledButton {
                text: "✕"
                theme: noteWindow.theme
                variant: "ghost"
                implicitHeight: 28
                implicitWidth: 28
                padding: 0
                font.pixelSize: 12
                onClicked: noteWindow.close()
            }
        }
    }

    Popup {
        id: noteSettingsPopup
        parent: noteWindow.contentItem
        x: Math.max(8, noteWindow.width - width - 8)
        y: 38
        width: Math.min(270, noteWindow.width - 16)
        height: Math.min(contentCol.implicitHeight + 20, Math.max(120, noteWindow.height - 46))
        padding: 10
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent | Popup.CloseOnPressOutside

        background: Rectangle {
            color: theme.surface
            radius: theme.radiusMd
            border.width: 1
            border.color: theme.border
        }

        contentItem: ScrollView {
            id: popupScroll
            anchors.fill: parent
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            contentWidth: availableWidth

            ColumnLayout {
                id: contentCol
                width: popupScroll.availableWidth
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: qsTr("Note Settings")
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: theme.textPrimary
                        Layout.fillWidth: true
                    }
                    Label {
                        text: "✕"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: closeHover.hovered ? theme.textPrimary : theme.textSecondary
                        MouseArea {
                            id: closeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: noteSettingsPopup.close()
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Label {
                        text: qsTr("Color Theme")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: theme.textSecondary
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { key: "yellow", name: qsTr("Yellow"), color: "#eab308" },
                                { key: "green",  name: qsTr("Green"),  color: "#22c55e" },
                                { key: "pink",   name: qsTr("Pink"),   color: "#ec4899" },
                                { key: "blue",   name: qsTr("Blue"),   color: "#0ea5e9" },
                                { key: "purple", name: qsTr("Purple"), color: "#a855f7" }
                            ]
                            delegate: Rectangle {
                                required property var modelData
                                width: 32
                                height: 32
                                radius: 16
                                color: modelData.color
                                border.width: noteWindow.noteTint === modelData.key ? 3 : 1
                                border.color: noteWindow.noteTint === modelData.key ? theme.textPrimary : (theme.isDark ? "#444" : "#ddd")
                                scale: swatchHover.hovered ? 1.15 : 1.0
                                Behavior on scale { NumberAnimation { duration: 100 } }

                                Label {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: modelData.key === "yellow" ? "#1e293b" : "#ffffff"
                                    visible: noteWindow.noteTint === modelData.key
                                }

                                MouseArea {
                                    id: swatchHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        noteWindow.noteTint = modelData.key
                                        backend.setNoteColor(modelData.key)
                                        autosave.restart()
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: theme.border
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: theme.radiusSm
                        color: aotHover.hovered ? theme.surfaceHover : theme.surface
                        border.width: 1
                        border.color: noteWindow.alwaysOnTop ? theme.accent : theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6
                            Label { text: "📍"; font.pixelSize: 13 }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("Layer")
                                    font.pixelSize: 10
                                    color: theme.textSecondary
                                }
                                Label {
                                    text: noteWindow.alwaysOnTop ? qsTr("On Top") : qsTr("On Desktop")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: noteWindow.alwaysOnTop ? theme.accent : theme.textPrimary
                                }
                            }
                        }
                        MouseArea {
                            id: aotHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: noteWindow.alwaysOnTop = !noteWindow.alwaysOnTop
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: theme.radiusSm
                        color: pinFavHover.hovered ? theme.surfaceHover : theme.surface
                        border.width: 1
                        border.color: backend.isPinned ? theme.accent : theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6
                            Label { text: "📌"; font.pixelSize: 13 }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("Favorites")
                                    font.pixelSize: 10
                                    color: theme.textSecondary
                                }
                                Label {
                                    text: backend.isPinned ? qsTr("Pinned") : qsTr("Unpinned")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: backend.isPinned ? theme.accent : theme.textPrimary
                                }
                            }
                        }
                        MouseArea {
                            id: pinFavHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                backend.setPinned(!backend.isPinned)
                                autosave.restart()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: theme.radiusSm
                        color: remCardHover.hovered ? theme.surfaceHover : theme.surface
                        border.width: 1
                        border.color: theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6
                            Label { text: "⏰"; font.pixelSize: 13 }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("Reminder")
                                    font.pixelSize: 10
                                    color: theme.textSecondary
                                }
                                Label {
                                    text: qsTr("+1 Hour")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: theme.textPrimary
                                }
                            }
                        }
                        MouseArea {
                            id: remCardHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const nowSec = Math.round(Date.now() / 1000)
                                backend.setReminder(nowSec + 3600, "none")
                                backend.sendNotification(qsTr("Reminder set"), qsTr("We will remind you in 1 hour."))
                                noteSettingsPopup.close()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: theme.radiusSm
                        color: copyCardHover.hovered ? theme.surfaceHover : theme.surface
                        border.width: 1
                        border.color: theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6
                            Label { text: "📋"; font.pixelSize: 13 }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("Clipboard")
                                    font.pixelSize: 10
                                    color: theme.textSecondary
                                }
                                Label {
                                    text: qsTr("Copy Text")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: theme.textPrimary
                                }
                            }
                        }
                        MouseArea {
                            id: copyCardHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                backend.copyToClipboard(backend.draftContent)
                                backend.sendNotification(qsTr("Copied to clipboard"), backend.draftTitle || qsTr("Note content copied"))
                                noteSettingsPopup.close()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: theme.radiusSm
                        color: libCardHover.hovered ? theme.surfaceHover : theme.surface
                        border.width: 1
                        border.color: theme.border

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6
                            Label { text: "📚"; font.pixelSize: 13 }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("All Notes")
                                    font.pixelSize: 10
                                    color: theme.textSecondary
                                }
                                Label {
                                    text: qsTr("Library")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: theme.textPrimary
                                }
                            }
                        }
                        MouseArea {
                            id: libCardHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                noteSettingsPopup.close()
                                noteWindow.libraryRequested()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 38
                        radius: theme.radiusSm
                        color: delCardHover.hovered ? theme.dangerHover : theme.dangerSubtle
                        border.width: 1
                        border.color: theme.danger

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6
                            Label { text: "🗑️"; font.pixelSize: 13 }
                            ColumnLayout {
                                spacing: 0
                                Layout.fillWidth: true
                                Label {
                                    text: qsTr("Delete")
                                    font.pixelSize: 10
                                    color: delCardHover.hovered ? theme.dangerText : theme.danger
                                }
                                Label {
                                    text: qsTr("Remove")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: delCardHover.hovered ? theme.dangerText : theme.danger
                                }
                            }
                        }
                        MouseArea {
                            id: delCardHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                noteSettingsPopup.close()
                                noteWindow.showDialog(deleteDialog)
                            }
                        }
                    }
                }
            }
        }
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
                width: Math.max(100, contentScroll.width)
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
    // Resize handles for frameless window
    MouseArea {
        id: rightResize
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: 16
        width: 8
        cursorShape: Qt.SizeHorCursor
        z: 20
        property int startW: 0
        property int startGlobalX: 0

        onPressed: function(mouse) {
            if (noteWindow.canPosition) {
                noteWindow.resizing = true
                startW = noteWindow.width
                startGlobalX = backend.cursorGlobalX()
            } else {
                noteWindow.startSystemResize(Qt.RightEdge)
            }
        }
        onPositionChanged: function(mouse) {
            if (pressed && noteWindow.canPosition) {
                var dx = backend.cursorGlobalX() - startGlobalX
                var newW = Math.round(Math.max(noteWindow.minimumWidth, startW + dx))
                if (noteWindow.width !== newW) noteWindow.width = newW
            }
        }
        onReleased: function() {
            if (noteWindow.canPosition) {
                noteWindow.resizing = false
                noteWindow.captureGeometry()
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
        property int startH: 0
        property int startGlobalY: 0

        onPressed: function(mouse) {
            if (noteWindow.canPosition) {
                noteWindow.resizing = true
                startH = noteWindow.height
                startGlobalY = backend.cursorGlobalY()
            } else {
                noteWindow.startSystemResize(Qt.BottomEdge)
            }
        }
        onPositionChanged: function(mouse) {
            if (pressed && noteWindow.canPosition) {
                var dy = backend.cursorGlobalY() - startGlobalY
                var newH = Math.round(Math.max(noteWindow.minimumHeight, startH + dy))
                if (noteWindow.height !== newH) noteWindow.height = newH
            }
        }
        onReleased: function() {
            if (noteWindow.canPosition) {
                noteWindow.resizing = false
                noteWindow.captureGeometry()
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
        property int startW: 0
        property int startH: 0
        property int startGlobalX: 0
        property int startGlobalY: 0

        onPressed: function(mouse) {
            if (noteWindow.canPosition) {
                noteWindow.resizing = true
                startW = noteWindow.width
                startH = noteWindow.height
                startGlobalX = backend.cursorGlobalX()
                startGlobalY = backend.cursorGlobalY()
            } else {
                noteWindow.startSystemResize(Qt.BottomEdge | Qt.RightEdge)
            }
        }
        onPositionChanged: function(mouse) {
            if (pressed && noteWindow.canPosition) {
                var dx = backend.cursorGlobalX() - startGlobalX
                var dy = backend.cursorGlobalY() - startGlobalY
                var newW = Math.round(Math.max(noteWindow.minimumWidth, startW + dx))
                var newH = Math.round(Math.max(noteWindow.minimumHeight, startH + dy))
                if (noteWindow.width !== newW) noteWindow.width = newW
                if (noteWindow.height !== newH) noteWindow.height = newH
            }
        }
        onReleased: function() {
            if (noteWindow.canPosition) {
                noteWindow.resizing = false
                noteWindow.captureGeometry()
            }
        }

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
        id: leftResize
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.bottomMargin: 16
        width: 8
        cursorShape: Qt.SizeHorCursor
        z: 20
        property int startW: 0
        property int startX: 0
        property int startGlobalX: 0

        onPressed: function(mouse) {
            if (noteWindow.canPosition) {
                noteWindow.resizing = true
                startW = noteWindow.width
                startX = noteWindow.x
                startGlobalX = backend.cursorGlobalX()
            } else {
                noteWindow.startSystemResize(Qt.LeftEdge)
            }
        }
        onPositionChanged: function(mouse) {
            if (pressed && noteWindow.canPosition) {
                var dx = backend.cursorGlobalX() - startGlobalX
                var newW = Math.round(startW - dx)
                if (newW >= noteWindow.minimumWidth) {
                    noteWindow.width = newW
                    noteWindow.x = Math.round(startX + dx)
                }
            }
        }
        onReleased: function() {
            if (noteWindow.canPosition) {
                noteWindow.resizing = false
                noteWindow.captureGeometry()
            }
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
        property int startW: 0
        property int startH: 0
        property int startX: 0
        property int startGlobalX: 0
        property int startGlobalY: 0

        onPressed: function(mouse) {
            if (noteWindow.canPosition) {
                noteWindow.resizing = true
                startW = noteWindow.width
                startH = noteWindow.height
                startX = noteWindow.x
                startGlobalX = backend.cursorGlobalX()
                startGlobalY = backend.cursorGlobalY()
            } else {
                noteWindow.startSystemResize(Qt.BottomEdge | Qt.LeftEdge)
            }
        }
        onPositionChanged: function(mouse) {
            if (pressed && noteWindow.canPosition) {
                var dy = backend.cursorGlobalY() - startGlobalY
                var newH = Math.round(Math.max(noteWindow.minimumHeight, startH + dy))
                if (noteWindow.height !== newH) noteWindow.height = newH

                var dx = backend.cursorGlobalX() - startGlobalX
                var newW = Math.round(startW - dx)
                if (newW >= noteWindow.minimumWidth) {
                    noteWindow.width = newW
                    noteWindow.x = Math.round(startX + dx)
                }
            }
        }
        onReleased: function() {
            if (noteWindow.canPosition) {
                noteWindow.resizing = false
                noteWindow.captureGeometry()
            }
        }
    }

    Shortcut { sequences: [StandardKey.Save]; context: Qt.WindowShortcut; onActivated: noteWindow.flush() && noteWindow.persist(true) }
    Shortcut { sequences: [StandardKey.Close]; context: Qt.WindowShortcut; onActivated: noteWindow.close() }
    Shortcut { sequences: [StandardKey.Quit]; context: Qt.WindowShortcut; onActivated: noteWindow.quitRequested() }
}
