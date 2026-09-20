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
    width: 440
    height: 520
    minimumWidth: 380
    minimumHeight: 460
    color: "transparent"
    visible: false

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
        radius: theme.radiusLg
        color: theme.surface
        border.width: 1
        border.color: theme.border

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header Bar
            Rectangle {
                Layout.fillWidth: true
                height: 48
                color: theme.surfaceElevated
                radius: theme.radiusLg

                // Square off bottom corners so only top is rounded
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: theme.radiusLg
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
                    spacing: 10

                    Rectangle {
                        width: 28
                        height: 28
                        radius: theme.radiusSm
                        color: theme.accentSubtle
                        UI.AppIcon {
                            anchors.centerIn: parent
                            name: "settings"
                            size: 16
                            color: theme.accent
                        }
                    }

                    ColumnLayout {
                        spacing: 0
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
                        iconSize: 14
                        theme: modalRoot.theme
                        variant: "ghost"
                        implicitWidth: 28
                        implicitHeight: 28
                        padding: 0
                        onClicked: modalRoot.close()
                    }
                }
            }

            // Scrollable Settings Content
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

                    // SECTION 1: Color Themes
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: qsTr("NOTE COLOR")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: theme.textSecondary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Repeater {
                                model: [
                                    { key: "yellow", name: qsTr("Yellow"), color: "#eab308", border: "#ca8a04" },
                                    { key: "green",  name: qsTr("Green"),  color: "#22c55e", border: "#16a34a" },
                                    { key: "pink",   name: qsTr("Pink"),   color: "#ec4899", border: "#db2777" },
                                    { key: "blue",   name: qsTr("Blue"),   color: "#0ea5e9", border: "#0284c7" },
                                    { key: "purple", name: qsTr("Purple"), color: "#a855f7", border: "#9333ea" }
                                ]

                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    height: 58
                                    radius: theme.radiusMd
                                    color: colorArea.hovered ? theme.surfaceHover : theme.surfaceElevated
                                    border.width: (noteWindow.noteTint === modelData.key) ? 2 : 1
                                    border.color: (noteWindow.noteTint === modelData.key) ? theme.accent : theme.border

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Rectangle {
                                            Layout.alignment: Qt.AlignHCenter
                                            width: 26
                                            height: 26
                                            radius: 13
                                            color: modelData.color
                                            border.width: 1
                                            border.color: Qt.darker(modelData.color, 1.2)

                                            UI.AppIcon {
                                                anchors.centerIn: parent
                                                name: "check"
                                                size: 14
                                                color: "#ffffff"
                                                strokeWidth: 2.4
                                                visible: noteWindow.noteTint === modelData.key
                                            }
                                        }

                                        Label {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.name
                                            font.pixelSize: 10
                                            font.weight: (noteWindow.noteTint === modelData.key) ? Font.Bold : Font.Normal
                                            color: (noteWindow.noteTint === modelData.key) ? theme.textPrimary : theme.textSecondary
                                        }
                                    }

                                    MouseArea {
                                        id: colorArea
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

                    // SECTION 2: Window Behavior
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: qsTr("WINDOW & DESKTOP BEHAVIOR")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: theme.textSecondary
                        }

                        // Always on Top Card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 52
                            radius: theme.radiusMd
                            color: topHover.hovered ? theme.surfaceHover : theme.surfaceElevated
                            border.width: 1
                            border.color: noteWindow.alwaysOnTop ? theme.accent : theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: theme.radiusSm
                                    color: noteWindow.alwaysOnTop ? theme.accentSubtle : theme.surface
                                    UI.AppIcon {
                                        anchors.centerIn: parent
                                        name: "pin"
                                        size: 16
                                        color: noteWindow.alwaysOnTop ? theme.accent : theme.textSecondary
                                    }
                                }

                                ColumnLayout {
                                    spacing: 1
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

                                // Interactive toggle switch
                                Rectangle {
                                    width: 36
                                    height: 20
                                    radius: 10
                                    color: noteWindow.alwaysOnTop ? theme.accent : theme.border
                                    Rectangle {
                                        x: noteWindow.alwaysOnTop ? 18 : 2
                                        y: 2
                                        width: 16
                                        height: 16
                                        radius: 8
                                        color: "#ffffff"
                                        Behavior on x { NumberAnimation { duration: 150 } }
                                    }
                                }
                            }

                            MouseArea {
                                id: topHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: noteWindow.alwaysOnTop = !noteWindow.alwaysOnTop
                            }
                        }

                        // Compact Mode Card
                        Rectangle {
                            Layout.fillWidth: true
                            height: 52
                            radius: theme.radiusMd
                            color: collapseHover.hovered ? theme.surfaceHover : theme.surfaceElevated
                            border.width: 1
                            border.color: noteWindow.collapsed ? theme.accent : theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: theme.radiusSm
                                    color: noteWindow.collapsed ? theme.accentSubtle : theme.surface
                                    UI.AppIcon {
                                        anchors.centerIn: parent
                                        name: noteWindow.collapsed ? "chevron-up" : "chevron-down"
                                        size: 16
                                        color: noteWindow.collapsed ? theme.accent : theme.textSecondary
                                    }
                                }

                                ColumnLayout {
                                    spacing: 1
                                    Layout.fillWidth: true
                                    Label {
                                        text: qsTr("Compact Header Mode")
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: theme.textPrimary
                                    }
                                    Label {
                                        text: noteWindow.collapsed ? qsTr("Collapsed to title bar only") : qsTr("Full note editor visible")
                                        font.pixelSize: 10
                                        color: theme.textSecondary
                                    }
                                }

                                Rectangle {
                                    width: 36
                                    height: 20
                                    radius: 10
                                    color: noteWindow.collapsed ? theme.accent : theme.border
                                    Rectangle {
                                        x: noteWindow.collapsed ? 18 : 2
                                        y: 2
                                        width: 16
                                        height: 16
                                        radius: 8
                                        color: "#ffffff"
                                        Behavior on x { NumberAnimation { duration: 150 } }
                                    }
                                }
                            }

                            MouseArea {
                                id: collapseHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: noteWindow.toggleCollapsed()
                            }
                        }
                    }

                    // SECTION 3: Quick Actions
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: qsTr("ACTIONS")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: theme.textSecondary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: theme.radiusMd
                                color: copyCardArea.hovered ? theme.surfaceHover : theme.surfaceElevated
                                border.width: 1
                                border.color: theme.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8
                                    UI.AppIcon { name: "copy"; size: 16; color: theme.accent }
                                    Label {
                                        text: qsTr("Copy Text")
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: theme.textPrimary
                                    }
                                }

                                MouseArea {
                                    id: copyCardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        backend.copyToClipboard(backend.draftContent)
                                        backend.sendNotification(qsTr("Copied to clipboard"), backend.draftTitle || qsTr("Note content copied"))
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: theme.radiusMd
                                color: libCardArea.hovered ? theme.surfaceHover : theme.surfaceElevated
                                border.width: 1
                                border.color: theme.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8
                                    UI.AppIcon { name: "library"; size: 16; color: theme.accent }
                                    Label {
                                        text: qsTr("All Notes")
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: theme.textPrimary
                                    }
                                }

                                MouseArea {
                                    id: libCardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        modalRoot.close()
                                        noteWindow.libraryRequested()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 44
                                radius: theme.radiusMd
                                color: remindCardArea.hovered ? theme.surfaceHover : theme.surfaceElevated
                                border.width: 1
                                border.color: theme.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 8
                                    UI.AppIcon { name: "clock"; size: 16; color: theme.accent }
                                    Label {
                                        text: qsTr("Remind +1h")
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                        color: theme.textPrimary
                                    }
                                }

                                MouseArea {
                                    id: remindCardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        backend.setQuickReminder(3600)
                                        backend.sendNotification(qsTr("Reminder Set"), qsTr("BetterNotes will remind you in 1 hour"))
                                    }
                                }
                            }
                        }
                    }

                    // SECTION 4: Danger Zone
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            text: qsTr("DANGER ZONE")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: theme.danger
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 46
                            radius: theme.radiusMd
                            color: deleteCardArea.hovered ? theme.dangerHover : theme.dangerSubtle
                            border.width: 1
                            border.color: theme.danger

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                UI.AppIcon {
                                    name: "trash"
                                    size: 16
                                    color: deleteCardArea.hovered ? theme.dangerText : theme.danger
                                }

                                ColumnLayout {
                                    spacing: 0
                                    Layout.fillWidth: true
                                    Label {
                                        text: qsTr("Delete Note")
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: deleteCardArea.hovered ? theme.dangerText : theme.danger
                                    }
                                    Label {
                                        text: qsTr("Permanently delete this note and close its window")
                                        font.pixelSize: 9
                                        color: deleteCardArea.hovered ? theme.dangerText : theme.textSecondary
                                    }
                                }
                            }

                            MouseArea {
                                id: deleteCardArea
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

                    Item { height: 6 }
                }
            }

            // Footer Bar
            Rectangle {
                Layout.fillWidth: true
                height: 48
                color: theme.surfaceElevated
                radius: theme.radiusLg

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: theme.radiusLg
                    color: parent.color
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: theme.border
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Label {
                        Layout.fillWidth: true
                        property int wordCount: backend.draftContent.trim().length ? backend.draftContent.trim().split(/\s+/).length : 0
                        property int charCount: backend.draftContent.length
                        text: wordCount + " " + qsTr("words") + " • " + charCount + " " + qsTr("characters")
                        font.pixelSize: 11
                        color: theme.textSecondary
                    }

                    UI.StyledButton {
                        text: qsTr("Done")
                        variant: "accent"
                        theme: modalRoot.theme
                        implicitWidth: 80
                        implicitHeight: 32
                        onClicked: modalRoot.close()
                    }
                }
            }
        }
    }
}
