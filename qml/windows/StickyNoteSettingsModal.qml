import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components" as UI
import "../themes" as Themes

Window {
    id: modalRoot

    required property var noteWindow
    required property var backend
    required property Themes.Theme theme

    title: qsTr("Note Settings") + (backend.draftTitle.length ? " — " + backend.draftTitle : "")
    flags: Qt.Dialog | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    modality: Qt.NonModal
    width: 460
    height: 580
    minimumWidth: 400
    minimumHeight: 500
    color: "transparent"
    visible: false

    property int currentTab: 0 // 0: Appearance, 1: Window, 2: Actions

    Shortcut {
        sequence: "Escape"
        onActivated: modalRoot.close()
    }

    function openCentered(target) {
        if (target) {
            var screenTarget = target.screen || Screen
            var cx = target.x + Math.round((target.width - modalRoot.width) / 2)
            var cy = target.y + Math.round((target.height - modalRoot.height) / 2)
            if (screenTarget) {
                cx = Math.max(screenTarget.virtualX + 20, Math.min(cx, screenTarget.virtualX + screenTarget.width - modalRoot.width - 20))
                cy = Math.max(screenTarget.virtualY + 40, Math.min(cy, screenTarget.virtualY + screenTarget.height - modalRoot.height - 40))
            }
            modalRoot.x = cx
            modalRoot.y = cy
        }
        modalRoot.show()
        modalRoot.raise()
        modalRoot.requestActivate()
    }

    Rectangle {
        id: container
        anchors.fill: parent
        anchors.margins: 6
        radius: 16
        color: theme.surface
        border.width: 1
        border.color: theme.border

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ==========================================
            // HEADER BAR
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                height: 52
                color: theme.surfaceElevated
                radius: 16

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 16
                    color: parent.color
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: theme.border
                }

                MouseArea {
                    anchors.fill: parent
                    property point clickPos: Qt.point(0, 0)
                    onPressed: clickPos = Qt.point(mouse.x, mouse.y)
                    onPositionChanged: {
                        modalRoot.x += mouse.x - clickPos.x
                        modalRoot.y += mouse.y - clickPos.y
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 12

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 8
                        color: theme.accentSubtle

                        UI.AppIcon {
                            anchors.centerIn: parent
                            name: "settings"
                            size: 16
                            color: theme.accent
                        }
                    }

                    ColumnLayout {
                        spacing: 1
                        Layout.fillWidth: true

                        Label {
                            text: qsTr("Note Settings")
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            color: theme.textPrimary
                        }
                        Label {
                            text: backend.draftTitle.trim() || qsTr("Untitled Note")
                            font.pixelSize: 11
                            color: theme.textSecondary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    UI.StyledButton {
                        iconName: "x"
                        iconSize: 15
                        theme: modalRoot.theme
                        variant: "ghost"
                        implicitWidth: 30
                        implicitHeight: 30
                        padding: 0
                        onClicked: modalRoot.close()
                    }
                }
            }

            // ==========================================
            // SEGMENTED TAB BAR
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                height: 44
                color: theme.surface
                border.width: 0

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: theme.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    // TAB 0: Appearance
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: modalRoot.currentTab === 0 ? theme.surfaceElevated : (tab0Hover.hovered ? theme.surfaceHover : "transparent")
                        border.width: modalRoot.currentTab === 0 ? 1 : 0
                        border.color: theme.border

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            UI.AppIcon {
                                name: "palette"
                                size: 14
                                color: modalRoot.currentTab === 0 ? theme.accent : theme.textSecondary
                            }
                            Label {
                                text: qsTr("Appearance")
                                font.pixelSize: 12
                                font.weight: modalRoot.currentTab === 0 ? Font.DemiBold : Font.Normal
                                color: modalRoot.currentTab === 0 ? theme.textPrimary : theme.textSecondary
                            }
                        }

                        MouseArea {
                            id: tab0Hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modalRoot.currentTab = 0
                        }
                    }

                    // TAB 1: Window
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: modalRoot.currentTab === 1 ? theme.surfaceElevated : (tab1Hover.hovered ? theme.surfaceHover : "transparent")
                        border.width: modalRoot.currentTab === 1 ? 1 : 0
                        border.color: theme.border

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            UI.AppIcon {
                                name: "pin"
                                size: 14
                                color: modalRoot.currentTab === 1 ? theme.accent : theme.textSecondary
                            }
                            Label {
                                text: qsTr("Window")
                                font.pixelSize: 12
                                font.weight: modalRoot.currentTab === 1 ? Font.DemiBold : Font.Normal
                                color: modalRoot.currentTab === 1 ? theme.textPrimary : theme.textSecondary
                            }
                        }

                        MouseArea {
                            id: tab1Hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modalRoot.currentTab = 1
                        }
                    }

                    // TAB 2: Actions
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        color: modalRoot.currentTab === 2 ? theme.surfaceElevated : (tab2Hover.hovered ? theme.surfaceHover : "transparent")
                        border.width: modalRoot.currentTab === 2 ? 1 : 0
                        border.color: theme.border

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            UI.AppIcon {
                                name: "sliders"
                                size: 14
                                color: modalRoot.currentTab === 2 ? theme.accent : theme.textSecondary
                            }
                            Label {
                                text: qsTr("Actions")
                                font.pixelSize: 12
                                font.weight: modalRoot.currentTab === 2 ? Font.DemiBold : Font.Normal
                                color: modalRoot.currentTab === 2 ? theme.textPrimary : theme.textSecondary
                            }
                        }

                        MouseArea {
                            id: tab2Hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modalRoot.currentTab = 2
                        }
                    }
                }
            }

            // ==========================================
            // TAB CONTENT AREA
            // ==========================================
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                ColumnLayout {
                    width: parent.width
                    spacing: 16
                    Layout.margins: 16

                    Item { height: 2 }

                    // ==========================================
                    // TAB 0: APPEARANCE (Color Palette & Fonts)
                    // ==========================================
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        visible: modalRoot.currentTab === 0

                        // --- 1. COLOR PRESETS ---
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: qsTr("COLOR PRESETS")
                                font.pixelSize: 11
                                font.weight: Font.Bold
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
                                        Layout.fillWidth: true
                                        height: 48
                                        radius: 10
                                        color: cpArea.hovered ? theme.surfaceHover : theme.surfaceElevated
                                        border.width: (noteWindow.noteTint === modelData.key) ? 2 : 1
                                        border.color: (noteWindow.noteTint === modelData.key) ? theme.accent : theme.border

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Rectangle {
                                                width: 22
                                                height: 22
                                                radius: 11
                                                color: modelData.color
                                                border.width: 1
                                                border.color: Qt.darker(modelData.color, 1.2)

                                                UI.AppIcon {
                                                    anchors.centerIn: parent
                                                    name: "check"
                                                    size: 13
                                                    color: "#ffffff"
                                                    strokeWidth: 2.5
                                                    visible: noteWindow.noteTint === modelData.key
                                                }
                                            }

                                            Label {
                                                text: modelData.name
                                                font.pixelSize: 11
                                                font.weight: (noteWindow.noteTint === modelData.key) ? Font.Bold : Font.Normal
                                                color: (noteWindow.noteTint === modelData.key) ? theme.textPrimary : theme.textSecondary
                                            }
                                        }

                                        MouseArea {
                                            id: cpArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                noteWindow.noteTint = modelData.key
                                                backend.setNoteColor(modelData.key)
                                                noteWindow.persist(true)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // --- 2. EXTENDED PALETTE & CUSTOM COLOR PICKER ---
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: qsTr("CUSTOM COLOR & EXTENDED PALETTE")
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: theme.textSecondary
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: 12
                                color: theme.surfaceElevated
                                border.width: 1
                                border.color: theme.border
                                implicitHeight: customColLayout.implicitHeight + 24

                                ColumnLayout {
                                    id: customColLayout
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    // 12 Curated Pastel & Accent Swatches
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 6
                                        rowSpacing: 8
                                        columnSpacing: 8

                                        Repeater {
                                            model: [
                                                "#f43f5e", "#f97316", "#eab308", "#84cc16", "#10b981", "#06b6d4",
                                                "#3b82f6", "#6366f1", "#8b5cf6", "#d946ef", "#64748b", "#334155"
                                            ]

                                            delegate: Rectangle {
                                                required property string modelData
                                                Layout.fillWidth: true
                                                height: 32
                                                radius: 8
                                                color: modelData
                                                border.width: (noteWindow.noteTint.toLowerCase() === modelData.toLowerCase()) ? 2 : 1
                                                border.color: (noteWindow.noteTint.toLowerCase() === modelData.toLowerCase()) ? "#ffffff" : Qt.darker(modelData, 1.3)

                                                UI.AppIcon {
                                                    anchors.centerIn: parent
                                                    name: "check"
                                                    size: 14
                                                    color: "#ffffff"
                                                    strokeWidth: 2.5
                                                    visible: noteWindow.noteTint.toLowerCase() === modelData.toLowerCase()
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        noteWindow.noteTint = modelData
                                                        backend.setNoteColor(modelData)
                                                        hexField.text = modelData
                                                        noteWindow.persist(true)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Custom Hex Color Input Row
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Rectangle {
                                            width: 32
                                            height: 32
                                            radius: 16
                                            color: (noteWindow.noteTint.startsWith("#")) ? noteWindow.noteTint : "#eab308"
                                            border.width: 1
                                            border.color: theme.border
                                        }

                                        TextField {
                                            id: hexField
                                            Layout.fillWidth: true
                                            placeholderText: "#RRGGBB (e.g. #8B5CF6)"
                                            text: noteWindow.noteTint.startsWith("#") ? noteWindow.noteTint : ""
                                            font.pixelSize: 12
                                            color: theme.textPrimary
                                            placeholderTextColor: theme.textSecondary
                                            selectByMouse: true
                                            background: Rectangle {
                                                color: theme.surface
                                                border.width: hexField.activeFocus ? 1.5 : 1
                                                border.color: hexField.activeFocus ? theme.accent : theme.border
                                                radius: 8
                                            }
                                            onTextChanged: {
                                                var val = text.trim()
                                                if (!val.startsWith("#") && val.length > 0) val = "#" + val
                                                if (/^#[0-9A-Fa-f]{6}$/.test(val)) {
                                                    noteWindow.noteTint = val
                                                    backend.setNoteColor(val)
                                                    noteWindow.persist(true)
                                                }
                                            }
                                        }

                                        UI.StyledButton {
                                            text: qsTr("Apply")
                                            theme: modalRoot.theme
                                            variant: "accent"
                                            implicitHeight: 32
                                            onClicked: {
                                                var val = hexField.text.trim()
                                                if (!val.startsWith("#") && val.length > 0) val = "#" + val
                                                if (/^#[0-9A-Fa-f]{6}$/.test(val)) {
                                                    noteWindow.noteTint = val
                                                    backend.setNoteColor(val)
                                                    noteWindow.persist(true)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // --- 3. TYPOGRAPHY (FONT FAMILY & FONT SIZE) ---
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Label {
                                text: qsTr("TYPOGRAPHY (FONT & SIZE)")
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: theme.textSecondary
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: 12
                                color: theme.surfaceElevated
                                border.width: 1
                                border.color: theme.border
                                implicitHeight: typoLayout.implicitHeight + 24

                                ColumnLayout {
                                    id: typoLayout
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    // Font Family Selector Cards
                                    Label {
                                        text: qsTr("Font Family")
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: theme.textSecondary
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 2
                                        rowSpacing: 8
                                        columnSpacing: 8

                                        Repeater {
                                            model: [
                                                { name: qsTr("System (Default)"), family: "default", fontSample: "Sans" },
                                                { name: qsTr("Sans-Serif (Inter)"), family: "Inter", fontSample: "Inter" },
                                                { name: qsTr("Monospace (Code)"),  family: "Monospace", fontSample: "Monospace" },
                                                { name: qsTr("Serif (Classic)"),    family: "Serif", fontSample: "Serif" }
                                            ]

                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                height: 38
                                                radius: 8
                                                color: ffArea.hovered ? theme.surfaceHover : theme.surface
                                                border.width: (noteWindow.noteFontFamily === modelData.family) ? 2 : 1
                                                border.color: (noteWindow.noteFontFamily === modelData.family) ? theme.accent : theme.border

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 8
                                                    spacing: 6

                                                    Label {
                                                        text: modelData.name
                                                        font.family: (modelData.family === "default") ? "" : modelData.family
                                                        font.pixelSize: 11
                                                        font.weight: (noteWindow.noteFontFamily === modelData.family) ? Font.Bold : Font.Normal
                                                        color: (noteWindow.noteFontFamily === modelData.family) ? theme.textPrimary : theme.textSecondary
                                                        Layout.fillWidth: true
                                                    }

                                                    UI.AppIcon {
                                                        name: "check"
                                                        size: 13
                                                        color: theme.accent
                                                        strokeWidth: 2.4
                                                        visible: noteWindow.noteFontFamily === modelData.family
                                                    }
                                                }

                                                MouseArea {
                                                    id: ffArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        noteWindow.noteFontFamily = modelData.family
                                                        backend.setNoteFontFamily(modelData.family)
                                                        noteWindow.persist(true)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Font Size Stepper & Slider
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Label {
                                            text: qsTr("Font Size:")
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                            color: theme.textPrimary
                                        }

                                        UI.StyledButton {
                                            iconName: "minus"
                                            iconSize: 13
                                            theme: modalRoot.theme
                                            variant: "ghost"
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            padding: 0
                                            onClicked: {
                                                if (noteWindow.noteFontSize > 11) {
                                                    noteWindow.noteFontSize -= 1
                                                    backend.setNoteFontSize(noteWindow.noteFontSize)
                                                    noteWindow.persist(true)
                                                }
                                            }
                                        }

                                        Slider {
                                            id: sizeSlider
                                            Layout.fillWidth: true
                                            from: 11
                                            to: 22
                                            stepSize: 1
                                            value: noteWindow.noteFontSize > 0 ? noteWindow.noteFontSize : 13
                                            onMoved: {
                                                noteWindow.noteFontSize = Math.round(value)
                                                backend.setNoteFontSize(noteWindow.noteFontSize)
                                                noteWindow.persist(true)
                                            }
                                        }

                                        UI.StyledButton {
                                            iconName: "plus"
                                            iconSize: 13
                                            theme: modalRoot.theme
                                            variant: "ghost"
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            padding: 0
                                            onClicked: {
                                                if (noteWindow.noteFontSize < 22) {
                                                    noteWindow.noteFontSize += 1
                                                    backend.setNoteFontSize(noteWindow.noteFontSize)
                                                    noteWindow.persist(true)
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: 42
                                            height: 26
                                            radius: 6
                                            color: theme.surface
                                            border.width: 1
                                            border.color: theme.border
                                            Label {
                                                anchors.centerIn: parent
                                                text: (noteWindow.noteFontSize > 0 ? noteWindow.noteFontSize : 13) + "px"
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
                                                color: theme.textPrimary
                                            }
                                        }
                                    }

                                    // Live Typography Preview Box
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 52
                                        radius: 8
                                        color: noteWindow.activeBg
                                        border.width: 1
                                        border.color: noteWindow.activeBorder

                                        Label {
                                            anchors.centerIn: parent
                                            width: parent.width - 24
                                            text: qsTr("The quick brown fox jumps over the lazy dog.")
                                            font.family: (noteWindow.noteFontFamily === "default" || noteWindow.noteFontFamily === "") ? "" : noteWindow.noteFontFamily
                                            font.pixelSize: noteWindow.noteFontSize > 0 ? noteWindow.noteFontSize : 13
                                            color: theme.noteText
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ==========================================
                    // TAB 1: WINDOW BEHAVIOR
                    // ==========================================
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: modalRoot.currentTab === 1

                        Label {
                            text: qsTr("WINDOW BEHAVIOR")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: theme.textSecondary
                        }

                        // Always on Top Card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 58
                            radius: 12
                            color: topHover.hovered ? theme.surfaceHover : theme.surfaceElevated
                            border.width: 1
                            border.color: noteWindow.alwaysOnTop ? theme.accent : theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 8
                                    color: noteWindow.alwaysOnTop ? theme.accentSubtle : theme.surface
                                    UI.AppIcon {
                                        anchors.centerIn: parent
                                        name: "pin"
                                        size: 16
                                        color: noteWindow.alwaysOnTop ? theme.accent : theme.textSecondary
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Label {
                                        text: qsTr("Always on Top")
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: theme.textPrimary
                                    }
                                    Label {
                                        text: noteWindow.alwaysOnTop ? qsTr("Kept above all open windows") : qsTr("On desktop level (Always on Bottom)")
                                        font.pixelSize: 10
                                        color: theme.textSecondary
                                    }
                                }

                                Switch {
                                    checked: noteWindow.alwaysOnTop
                                    onToggled: {
                                        noteWindow.alwaysOnTop = checked
                                        noteWindow.persist(true)
                                    }
                                }
                            }

                            MouseArea {
                                id: topHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    noteWindow.alwaysOnTop = !noteWindow.alwaysOnTop
                                    noteWindow.persist(true)
                                }
                            }
                        }

                        // Compact Mode Card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 58
                            radius: 12
                            color: colHover.hovered ? theme.surfaceHover : theme.surfaceElevated
                            border.width: 1
                            border.color: noteWindow.collapsed ? theme.accent : theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 8
                                    color: noteWindow.collapsed ? theme.accentSubtle : theme.surface
                                    UI.AppIcon {
                                        anchors.centerIn: parent
                                        name: noteWindow.collapsed ? "chevron-down" : "chevron-up"
                                        size: 16
                                        color: noteWindow.collapsed ? theme.accent : theme.textSecondary
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Layout.fillWidth: true
                                    Label {
                                        text: qsTr("Compact Header Mode")
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: theme.textPrimary
                                    }
                                    Label {
                                        text: noteWindow.collapsed ? qsTr("Note is collapsed to a minimal titlebar") : qsTr("Full note editor is visible")
                                        font.pixelSize: 10
                                        color: theme.textSecondary
                                    }
                                }

                                Switch {
                                    checked: noteWindow.collapsed
                                    onToggled: noteWindow.toggleCollapsed()
                                }
                            }

                            MouseArea {
                                id: colHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: noteWindow.toggleCollapsed()
                            }
                        }

                        // Window Info Card
                        Rectangle {
                            Layout.fillWidth: true
                            radius: 12
                            color: theme.surfaceElevated
                            border.width: 1
                            border.color: theme.border
                            implicitHeight: winInfoLayout.implicitHeight + 24

                            ColumnLayout {
                                id: winInfoLayout
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Label {
                                    text: qsTr("Window Metrics")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: theme.textSecondary
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: qsTr("Size:"); font.pixelSize: 11; color: theme.textSecondary }
                                    Label { text: Math.round(noteWindow.width) + " × " + Math.round(noteWindow.height) + " px"; font.pixelSize: 11; font.weight: Font.Bold; color: theme.textPrimary }
                                    Item { Layout.fillWidth: true }
                                    Label { text: qsTr("Position:"); font.pixelSize: 11; color: theme.textSecondary }
                                    Label { text: "(" + Math.round(noteWindow.x) + ", " + Math.round(noteWindow.y) + ")"; font.pixelSize: 11; font.weight: Font.Bold; color: theme.textPrimary }
                                }
                            }
                        }
                    }

                    // ==========================================
                    // TAB 2: ACTIONS & METRICS
                    // ==========================================
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: modalRoot.currentTab === 2

                        Label {
                            text: qsTr("NOTE STATISTICS")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: theme.textSecondary
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            radius: 12
                            color: theme.surfaceElevated
                            border.width: 1
                            border.color: theme.border
                            implicitHeight: statsLayout.implicitHeight + 24

                            RowLayout {
                                id: statsLayout
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label { text: qsTr("Characters"); font.pixelSize: 10; color: theme.textSecondary }
                                    Label {
                                        text: (backend.draftContent ? backend.draftContent.length : 0).toString()
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: theme.textPrimary
                                    }
                                }

                                Rectangle { width: 1; height: 32; color: theme.border }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label { text: qsTr("Words"); font.pixelSize: 10; color: theme.textSecondary }
                                    Label {
                                        text: {
                                            var text = backend.draftContent ? backend.draftContent.trim() : ""
                                            if (text.length === 0) return "0"
                                            var words = text.split(/\s+/)
                                            return words.length.toString()
                                        }
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: theme.textPrimary
                                    }
                                }

                                Rectangle { width: 1; height: 32; color: theme.border }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label { text: qsTr("Tags"); font.pixelSize: 10; color: theme.textSecondary }
                                    Label {
                                        text: (backend.tags ? backend.tags.length : 0).toString()
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                        color: theme.textPrimary
                                    }
                                }
                            }
                        }

                        Label {
                            text: qsTr("QUICK ACTIONS")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: theme.textSecondary
                        }

                        // Copy Note Content
                        Rectangle {
                            Layout.fillWidth: true
                            height: 44
                            radius: 10
                            color: copyHover.hovered ? theme.surfaceHover : theme.surfaceElevated
                            border.width: 1
                            border.color: theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                UI.AppIcon { name: "copy"; size: 15; color: theme.accent }
                                Label {
                                    text: qsTr("Copy Note Content to Clipboard")
                                    font.pixelSize: 12
                                    color: theme.textPrimary
                                    Layout.fillWidth: true
                                }
                            }

                            MouseArea {
                                id: copyHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    backend.copyToClipboard(backend.draftContent)
                                }
                            }
                        }

                        // Open in Library
                        Rectangle {
                            Layout.fillWidth: true
                            height: 44
                            radius: 10
                            color: libHover.hovered ? theme.surfaceHover : theme.surfaceElevated
                            border.width: 1
                            border.color: theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                UI.AppIcon { name: "library"; size: 15; color: theme.accent }
                                Label {
                                    text: qsTr("Open in Main Library Window")
                                    font.pixelSize: 12
                                    color: theme.textPrimary
                                    Layout.fillWidth: true
                                }
                            }

                            MouseArea {
                                id: libHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    modalRoot.close()
                                    noteWindow.libraryRequested()
                                }
                            }
                        }

                        // Danger Zone: Delete
                        Label {
                            text: qsTr("DANGER ZONE")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: theme.danger
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 44
                            radius: 10
                            color: delHover.hovered ? Qt.rgba(0.9, 0.2, 0.2, 0.15) : Qt.rgba(0.9, 0.2, 0.2, 0.08)
                            border.width: 1
                            border.color: Qt.rgba(0.9, 0.2, 0.2, 0.3)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10

                                UI.AppIcon { name: "trash"; size: 15; color: theme.danger }
                                Label {
                                    text: qsTr("Delete Note Permanently")
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: theme.danger
                                    Layout.fillWidth: true
                                }
                            }

                            MouseArea {
                                id: delHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    modalRoot.close()
                                    noteWindow.requestDeleteNote()
                                }
                            }
                        }
                    }

                    Item { height: 10 }
                }
            }
        }
    }
}
