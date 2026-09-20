pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../themes"

Popup {
    id: palette
    modal: true
    focus: true
    dim: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property Theme theme: null
    property var backend: null
    signal noteSelected(string noteId)
    signal actionTriggered(string action)

    x: Math.round((parent.width - width) / 2)
    y: Math.min(80, Math.round((parent.height - height) / 3))
    width: Math.min(540, parent.width - 40)
    height: Math.min(420, contentCol.implicitHeight + 24)
    padding: 12

    background: Rectangle {
        radius: palette.theme ? palette.theme.radiusLg : 12
        color: palette.theme ? palette.theme.surface : "#ffffff"
        border.width: 1
        border.color: palette.theme ? palette.theme.accentSubtle : "#cbd5e1"

        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: palette.theme ? palette.theme.radiusLg + 1 : 13
            color: "transparent"
            border.width: 1
            border.color: palette.theme ? palette.theme.border : "#e2e8f0"
            z: -1
        }
    }

    onOpened: {
        filterInput.text = ""
        filterInput.forceActiveFocus()
        rebuildCommands()
    }

    property var staticCommands: [
        { id: "new_note", title: qsTr("📝 New note"), subtitle: qsTr("Create a fresh desktop sticky note"), shortcut: "Ctrl+N" },
        { id: "quick_capture", title: qsTr("⚡ Quick capture"), subtitle: qsTr("Open fast note capture scratchpad"), shortcut: "Ctrl+Alt+Space" },
        { id: "show_all", title: qsTr("👁️ Show all notes"), subtitle: qsTr("Bring all sticky notes to front"), shortcut: "" },
        { id: "hide_all", title: qsTr("🙈 Hide all notes"), subtitle: qsTr("Minimize all sticky notes"), shortcut: "" },
        { id: "toggle_theme", title: qsTr("🎨 Toggle theme mode"), subtitle: qsTr("Cycle through system, light, and dark"), shortcut: "" },
        { id: "toggle_pin", title: qsTr("📌 Toggle pin"), subtitle: qsTr("Pin or unpin active note"), shortcut: "" },
        { id: "toggle_archive", title: qsTr("📦 Toggle archive"), subtitle: qsTr("Archive or unarchive active note"), shortcut: "" },
        { id: "delete_note", title: qsTr("🗑️ Delete active note"), subtitle: qsTr("Remove note permanently"), shortcut: "" }
    ]

    property var displayedItems: []

    function rebuildCommands() {
        const query = filterInput.text.trim().toLowerCase()
        const items = []
        for (let i = 0; i < staticCommands.length; ++i) {
            const cmd = staticCommands[i]
            if (query.length === 0 || cmd.title.toLowerCase().indexOf(query) !== -1 || cmd.subtitle.toLowerCase().indexOf(query) !== -1) {
                items.push({ type: "command", id: cmd.id, title: cmd.title, subtitle: cmd.subtitle, shortcut: cmd.shortcut })
            }
        }
        if (query.length > 0 && palette.backend) {
            palette.backend.search(query)
            const ids = palette.backend.searchResultIds
            const titles = palette.backend.searchResultTitles
            const snippets = palette.backend.searchResultSnippets
            for (let j = 0; j < ids.length; ++j) {
                items.push({
                    type: "search_result",
                    id: ids[j],
                    title: titles[j].length > 0 ? titles[j] : qsTr("Untitled note"),
                    subtitle: snippets[j],
                    shortcut: qsTr("Note #") + ids[j]
                })
            }
        }
        displayedItems = items
        commandList.currentIndex = items.length > 0 ? 0 : -1
    }

    function executeCurrent() {
        if (commandList.currentIndex < 0 || commandList.currentIndex >= displayedItems.length) return
        const item = displayedItems[commandList.currentIndex]
        palette.close()
        if (item.type === "command") {
            palette.actionTriggered(item.id)
        } else if (item.type === "search_result") {
            palette.noteSelected(item.id)
        }
    }

    contentItem: ColumnLayout {
        id: contentCol
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "🔍"
                font.pixelSize: 16
                color: palette.theme ? palette.theme.textSecondary : "#64748b"
            }

            TextField {
                id: filterInput
                Layout.fillWidth: true
                placeholderText: qsTr("Type a command or search notes... (Esc to close)")
                selectByMouse: true
                color: palette.theme ? palette.theme.textPrimary : "#0f172a"
                placeholderTextColor: palette.theme ? palette.theme.textSecondary : "#94a3b8"
                font.pixelSize: 14
                background: Rectangle {
                    color: "transparent"
                }
                onTextEdited: palette.rebuildCommands()
                Keys.onDownPressed: {
                    if (commandList.currentIndex < palette.displayedItems.length - 1) {
                        commandList.currentIndex += 1
                    }
                }
                Keys.onUpPressed: {
                    if (commandList.currentIndex > 0) {
                        commandList.currentIndex -= 1
                    }
                }
                Keys.onReturnPressed: palette.executeCurrent()
            }

            Label {
                text: "ESC"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: palette.theme ? palette.theme.textSecondary : "#94a3b8"
                padding: 4
                background: Rectangle {
                    radius: 4
                    color: palette.theme ? palette.theme.surfaceHover : "#f1f5f9"
                    border.width: 1
                    border.color: palette.theme ? palette.theme.border : "#e2e8f0"
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: palette.theme ? palette.theme.border : "#e2e8f0"
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(300, commandList.contentHeight)
            clip: true

            ListView {
                id: commandList
                model: palette.displayedItems
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: delegateItem
                    required property int index
                    required property var modelData

                    width: commandList.width
                    height: col.implicitHeight + 14
                    radius: palette.theme ? palette.theme.radiusSm : 6
                    color: {
                        if (commandList.currentIndex === index) {
                            return palette.theme ? palette.theme.surfaceActive : "#e0e7ff"
                        }
                        if (itemMouse.hovered) {
                            return palette.theme ? palette.theme.surfaceHover : "#f8fafc"
                        }
                        return "transparent"
                    }

                    RowLayout {
                        id: col
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: delegateItem.modelData.title
                                textFormat: Text.PlainText
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: palette.theme ? palette.theme.textPrimary : "#0f172a"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Label {
                                text: delegateItem.modelData.subtitle
                                textFormat: Text.PlainText
                                font.pixelSize: 11
                                color: palette.theme ? palette.theme.textSecondary : "#64748b"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                visible: delegateItem.modelData.subtitle.length > 0
                            }
                        }

                        Label {
                            text: delegateItem.modelData.shortcut
                            font.pixelSize: 11
                            color: palette.theme ? palette.theme.textSecondary : "#94a3b8"
                            visible: delegateItem.modelData.shortcut.length > 0
                        }
                    }

                    HoverHandler { id: itemMouse }

                    TapHandler {
                        onTapped: {
                            commandList.currentIndex = delegateItem.index
                            palette.executeCurrent()
                        }
                    }
                }
            }
        }
    }
}
