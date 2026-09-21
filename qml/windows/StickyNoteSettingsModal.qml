pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Templates as T
import "../components" as UI
import "../themes" as Themes

Window {
    id: modalRoot

    required property var noteWindow
    required property var backend
    required property Themes.Theme theme

    title: qsTr("Note settings")
    transientParent: modalRoot.noteWindow
    flags: Qt.Dialog | Qt.FramelessWindowHint
    modality: Qt.NonModal
    width: 480
    height: 680
    minimumWidth: 400
    minimumHeight: 440
    color: "transparent"
    visible: false
    palette.window: modalRoot.theme.surface
    palette.windowText: modalRoot.theme.textPrimary
    palette.text: modalRoot.theme.textPrimary
    palette.button: modalRoot.theme.surfaceElevated
    palette.buttonText: modalRoot.theme.textPrimary
    palette.base: modalRoot.theme.surface
    palette.highlight: modalRoot.theme.accent
    palette.highlightedText: modalRoot.theme.accentText
    palette.dark: modalRoot.theme.border

    property int currentTab: 0
    property int paletteIndex: 0
    property string appearanceError: ""
    readonly property var palettes: [
        [
            { key: "yellow", name: qsTr("Butter"), color: "#f3d66b" },
            { key: "green", name: qsTr("Mint"), color: "#91cda5" },
            { key: "pink", name: qsTr("Rose"), color: "#eaa6b9" },
            { key: "blue", name: qsTr("Sky"), color: "#95c9e8" },
            { key: "purple", name: qsTr("Lilac"), color: "#bda4de" },
            { key: "#e8ac85", name: qsTr("Peach"), color: "#e8ac85" }
        ],
        [
            { key: "#ef4444", name: qsTr("Red"), color: "#ef4444" },
            { key: "#f97316", name: qsTr("Orange"), color: "#f97316" },
            { key: "#eab308", name: qsTr("Gold"), color: "#eab308" },
            { key: "#10b981", name: qsTr("Emerald"), color: "#10b981" },
            { key: "#3b82f6", name: qsTr("Ocean"), color: "#3b82f6" },
            { key: "#8b5cf6", name: qsTr("Violet"), color: "#8b5cf6" }
        ],
        [
            { key: "#b97757", name: qsTr("Clay"), color: "#b97757" },
            { key: "#b59968", name: qsTr("Sand"), color: "#b59968" },
            { key: "#8c9a65", name: qsTr("Olive"), color: "#8c9a65" },
            { key: "#628c7a", name: qsTr("Sage"), color: "#628c7a" },
            { key: "#64748b", name: qsTr("Slate"), color: "#64748b" },
            { key: "#9b7e96", name: qsTr("Mauve"), color: "#9b7e96" }
        ]
    ]

    function chooseColor(value) {
        if (!modalRoot.backend.setNoteColor(value)) {
            appearanceError = qsTr("Could not save this color. Please try again.")
            return false
        }
        modalRoot.noteWindow.noteTint = value
        appearanceError = ""
        return true
    }

    function applyHex() {
        let value = hexField.text.trim()
        if (!value.startsWith("#")) value = "#" + value
        if (!/^#[0-9a-fA-F]{6}$/.test(value)) {
            appearanceError = qsTr("Enter a six-digit color, such as #8B5CF6.")
            return
        }
        chooseColor(value.toLowerCase())
    }

    function changeFont(family) {
        if (modalRoot.backend.setNoteFontFamily(family)) {
            modalRoot.noteWindow.noteFontFamily = family
            appearanceError = ""
        } else {
            appearanceError = qsTr("Could not save the font. Please try again.")
        }
    }

    function changeSize(size) {
        if (modalRoot.backend.setNoteFontSize(size)) {
            modalRoot.noteWindow.noteFontSize = size
            appearanceError = ""
        } else {
            appearanceError = qsTr("Could not save the font size. Please try again.")
        }
    }

    function openCentered(target) {
        if (target && target.screen) {
            screen = target.screen
            width = Math.max(minimumWidth, Math.min(480, screen.width - 40))
            height = Math.max(minimumHeight, Math.min(680, screen.height - 80))
            // Generic Wayland compositors own placement of top-level windows.
            if (target.canPosition) {
                x = Math.max(screen.virtualX + 20, Math.min(target.x + (target.width - width) / 2,
                    screen.virtualX + screen.width - width - 20))
                y = Math.max(screen.virtualY + 40, Math.min(target.y + (target.height - height) / 2,
                    screen.virtualY + screen.height - height - 40))
            }
        }
        show()
        raise()
        requestActivate()
    }

    Shortcut { sequence: "Escape"; enabled: !customColorDialog.visible; onActivated: modalRoot.close() }

    ColorDialog {
        id: customColorDialog
        title: qsTr("Choose a note color")
        options: ColorDialog.DontUseNativeDialog
        selectedColor: modalRoot.noteWindow.noteTint.startsWith("#") ? modalRoot.noteWindow.noteTint : modalRoot.noteWindow.activeHeader
        onAccepted: modalRoot.chooseColor(selectedColor.toString())
    }

    component SectionTitle: Label {
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: modalRoot.theme.textPrimary
        Layout.fillWidth: true
    }

    // Built on the template rather than the styled ComboBox: every visual part
    // is replaced here, and the KDE desktop style's ComboBox assumes its
    // content item is an editable TextInput (positionToRectangle), which a
    // plain Text is not.
    component SettingsCombo: T.ComboBox {
        id: combo
        implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                                implicitContentWidth + leftPadding + rightPadding)
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 32
        contentItem: Text {
            text: combo.displayText
            font.pixelSize: 12
            color: modalRoot.theme.textPrimary
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: UI.AppIcon {
            x: combo.width - width - 10
            y: (combo.height - height) / 2
            name: "chevron-down"
            size: 14
            color: modalRoot.theme.textSecondary
        }
        background: Rectangle {
            implicitWidth: 120
            radius: 8
            color: combo.hovered ? modalRoot.theme.surfaceHover : modalRoot.theme.surface
            border.color: combo.activeFocus ? modalRoot.theme.accent : modalRoot.theme.border
        }
        delegate: ItemDelegate {
            id: option
            required property int index
            required property string modelData
            width: combo.width - 12
            highlighted: combo.highlightedIndex === index
            contentItem: Text {
                text: option.modelData
                color: modalRoot.theme.textPrimary
                font.pixelSize: 12
            }
            background: Rectangle {
                radius: 6
                color: option.highlighted ? modalRoot.theme.accentSubtle : "transparent"
            }
        }
        popup: Popup {
            y: combo.height + 4
            width: combo.width
            padding: 6
            implicitHeight: contentItem.implicitHeight + 12
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
            }
            background: Rectangle {
                radius: 10
                color: modalRoot.theme.surface
                border.color: modalRoot.theme.border
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: 22
        antialiasing: true
        color: modalRoot.theme.surface
        border.width: 1
        border.color: modalRoot.theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 90

                MouseArea {
                    anchors.fill: parent
                    onPressed: modalRoot.startSystemMove()
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 20
                    spacing: 14

                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 14
                        color: modalRoot.theme.accentSubtle
                        UI.AppIcon { anchors.centerIn: parent; name: "settings"; size: 21; color: modalRoot.theme.accent }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: qsTr("Make it yours"); font.pixelSize: 21; font.weight: Font.DemiBold; color: modalRoot.theme.textPrimary }
                        Label {
                            Layout.fillWidth: true
                            text: modalRoot.backend.draftTitle.trim() || qsTr("Untitled note")
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            color: modalRoot.theme.textSecondary
                        }
                    }
                    UI.StyledButton {
                        iconName: "x"
                        theme: modalRoot.theme
                        variant: "ghost"
                        Accessible.name: qsTr("Close settings")
                        onClicked: modalRoot.close()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.preferredHeight: 42
                radius: 13
                color: modalRoot.theme.surfaceElevated
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4
                    Repeater {
                        model: [qsTr("Appearance"), qsTr("Window"), qsTr("Actions")]
                        delegate: UI.StyledButton {
                            required property int index
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: modelData
                            theme: modalRoot.theme
                            variant: modalRoot.currentTab === index ? "accent" : "ghost"
                            onClicked: modalRoot.currentTab = index
                        }
                    }
                }
            }

            ScrollView {
                id: settingsScroll
                objectName: "settingsScroll"
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                leftPadding: 24
                rightPadding: 24
                topPadding: 22
                bottomPadding: 24
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: settingsScroll.availableWidth
                    spacing: 20

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: modalRoot.currentTab === 0
                        spacing: 18

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: previewContent.implicitHeight + 36
                            radius: 16
                            color: modalRoot.noteWindow.activeBg
                            border.color: modalRoot.noteWindow.activeBorder
                            ColumnLayout {
                                id: previewContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 18
                                spacing: 10
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 8
                                    radius: 4
                                    color: modalRoot.noteWindow.activeHeader
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("A little space for your ideas.")
                                    wrapMode: Text.WordWrap
                                    font.family: modalRoot.noteWindow.noteFontFamily === "default" ? "" : modalRoot.noteWindow.noteFontFamily
                                    font.pixelSize: modalRoot.noteWindow.noteFontSize
                                    color: modalRoot.theme.noteText
                                }
                                Label { text: qsTr("Live preview · saved automatically"); font.pixelSize: 11; color: modalRoot.theme.noteTextSecondary }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            SectionTitle { text: qsTr("Color palette") }
                            SettingsCombo {
                                objectName: "paletteSelector"
                                model: [qsTr("Pastel"), qsTr("Vivid"), qsTr("Earth")]
                                currentIndex: modalRoot.paletteIndex
                                onActivated: modalRoot.paletteIndex = currentIndex
                                Accessible.name: qsTr("Color palette")
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: 10
                            rowSpacing: 10
                            Repeater {
                                model: modalRoot.palettes[modalRoot.paletteIndex]
                                delegate: AbstractButton {
                                    id: swatch
                                    required property var modelData
                                    readonly property bool selected: modalRoot.noteWindow.noteTint.toLowerCase() === modelData.key.toLowerCase()
                                    objectName: "colorSwatch_" + modelData.key
                                    Layout.fillWidth: true
                                    implicitHeight: 66
                                    Accessible.name: modelData.name
                                    Accessible.description: selected ? qsTr("Selected color") : qsTr("Use this note color")
                                    onClicked: modalRoot.chooseColor(modelData.key)
                                    background: Rectangle {
                                        radius: 12
                                        color: swatch.hovered ? modalRoot.theme.surfaceHover : modalRoot.theme.surfaceElevated
                                        border.width: swatch.selected || swatch.activeFocus ? 2 : 1
                                        border.color: swatch.selected || swatch.activeFocus ? modalRoot.theme.accent : modalRoot.theme.border
                                    }
                                    contentItem: ColumnLayout {
                                        spacing: 5
                                        Rectangle {
                                            Layout.alignment: Qt.AlignHCenter
                                            implicitWidth: 25
                                            implicitHeight: 25
                                            radius: 13
                                            color: swatch.modelData.color
                                            UI.AppIcon { anchors.centerIn: parent; name: "check"; size: 15; color: "#202024"; visible: swatch.selected }
                                        }
                                        Label { Layout.alignment: Qt.AlignHCenter; text: swatch.modelData.name; font.pixelSize: 11; color: modalRoot.theme.textSecondary }
                                    }
                                    padding: 8
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            UI.StyledButton {
                                objectName: "customColorButton"
                                text: qsTr("Custom…")
                                iconName: "droplet"
                                theme: modalRoot.theme
                                onClicked: customColorDialog.open()
                            }
                            UI.StyledTextField {
                                id: hexField
                                objectName: "hexColorField"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 60
                                theme: modalRoot.theme
                                placeholderText: "#RRGGBB"
                                text: modalRoot.noteWindow.noteTint.startsWith("#") ? modalRoot.noteWindow.noteTint : ""
                                Accessible.name: qsTr("Custom hexadecimal color")
                                onAccepted: modalRoot.applyHex()
                            }
                            UI.StyledButton { text: qsTr("Apply"); theme: modalRoot.theme; onClicked: modalRoot.applyHex() }
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: modalRoot.appearanceError.length > 0
                            text: modalRoot.appearanceError
                            wrapMode: Text.WordWrap
                            color: modalRoot.theme.danger
                            Accessible.role: Accessible.AlertMessage
                        }

                        SectionTitle { text: qsTr("Typography") }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: typography.implicitHeight + 32
                            radius: 14
                            color: modalRoot.theme.surfaceElevated
                            border.color: modalRoot.theme.border
                            ColumnLayout {
                                id: typography
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 16
                                spacing: 12
                                SettingsCombo {
                                    Layout.fillWidth: true
                                    model: [qsTr("System font"), qsTr("Sans serif (Inter)"), qsTr("Monospace"), qsTr("Serif")]
                                    readonly property var families: ["default", "Inter", "Monospace", "Serif"]
                                    currentIndex: Math.max(0, families.indexOf(modalRoot.noteWindow.noteFontFamily))
                                    onActivated: modalRoot.changeFont(families[currentIndex])
                                    Accessible.name: qsTr("Note font")
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: qsTr("Size"); color: modalRoot.theme.textSecondary; font.pixelSize: 12 }
                                    Slider {
                                        Layout.fillWidth: true
                                        from: 11
                                        to: 22
                                        stepSize: 1
                                        value: modalRoot.noteWindow.noteFontSize
                                        onMoved: modalRoot.changeSize(Math.round(value))
                                        Accessible.name: qsTr("Note font size")
                                    }
                                    Label { text: modalRoot.noteWindow.noteFontSize + " px"; color: modalRoot.theme.textPrimary; font.pixelSize: 12 }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: modalRoot.currentTab === 1
                        spacing: 16
                        SectionTitle { text: qsTr("Your desktop, your way") }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Keep the note nearby, or collapse it when you need more space.")
                            wrapMode: Text.WordWrap
                            color: modalRoot.theme.textSecondary
                        }
                        Switch {
                            Layout.fillWidth: true
                            text: qsTr("Keep above other windows")
                            checked: modalRoot.noteWindow.alwaysOnTop
                            onToggled: modalRoot.noteWindow.alwaysOnTop = checked
                        }
                        Switch {
                            Layout.fillWidth: true
                            text: qsTr("Compact header")
                            checked: modalRoot.noteWindow.collapsed
                            onToggled: modalRoot.noteWindow.toggleCollapsed()
                        }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Window placement and stacking depend on your desktop environment.")
                            wrapMode: Text.WordWrap
                            color: modalRoot.theme.textSecondary
                            font.pixelSize: 12
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: modalRoot.currentTab === 2
                        spacing: 14
                        SectionTitle { text: qsTr("Note at a glance") }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("%1 characters · %2 words").arg(modalRoot.noteWindow.plainContent.length)
                                .arg(modalRoot.noteWindow.plainContent.trim().length ? modalRoot.noteWindow.plainContent.trim().split(/\s+/).length : 0)
                            color: modalRoot.theme.textSecondary
                            wrapMode: Text.WordWrap
                        }
                        UI.StyledButton {
                            Layout.fillWidth: true
                            text: qsTr("Copy note text")
                            iconName: "copy"
                            theme: modalRoot.theme
                            onClicked: modalRoot.backend.copyToClipboard(modalRoot.noteWindow.plainContent)
                        }
                        UI.StyledButton {
                            Layout.fillWidth: true
                            text: qsTr("Open note library")
                            iconName: "library"
                            theme: modalRoot.theme
                            onClicked: { modalRoot.close(); modalRoot.noteWindow.libraryRequested() }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: modalRoot.theme.border; Layout.topMargin: 10; Layout.bottomMargin: 10 }
                        UI.StyledButton {
                            Layout.fillWidth: true
                            text: qsTr("Delete note…")
                            iconName: "trash"
                            theme: modalRoot.theme
                            variant: "danger"
                            onClicked: { modalRoot.close(); modalRoot.noteWindow.requestDeleteNote() }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 10
                Layout.bottomMargin: 18
                Label { Layout.fillWidth: true; text: qsTr("Just for this note"); font.pixelSize: 11; color: modalRoot.theme.textSecondary }
                UI.StyledButton { text: qsTr("Done"); theme: modalRoot.theme; variant: "accent"; onClicked: modalRoot.close() }
            }
        }
    }
}
