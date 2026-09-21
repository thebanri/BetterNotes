pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../themes"
import "Reminders.js" as Reminders

// Sets, changes or removes one note's reminder: a date, a time and whether it
// repeats. The owner stores the result; this only collects and checks it.
Popup {
    id: editor

    property Theme theme: null
    property string noteTitle: ""
    property bool hasReminder: false
    property string error: ""

    // Seconds since the epoch and "none", "daily", "weekly" or "monthly".
    signal saveRequested(real seconds, string recurrence)
    signal removeRequested()

    function openFor(title, stored) {
        noteTitle = title
        const reminder = Reminders.parse(stored)
        hasReminder = reminder !== null
        const date = reminder ? reminder.date : Reminders.presets()[0].date
        dateField.text = Reminders.dateText(date)
        timeField.text = Reminders.timeText(date)
        repeatBox.currentIndex = Math.max(0, repeatBox.indexOfValue(reminder ? reminder.recurrence : "none"))
        error = ""
        open()
        timeField.forceActiveFocus()
    }

    function choose(date) {
        dateField.text = Reminders.dateText(date)
        timeField.text = Reminders.timeText(date)
        error = ""
    }

    function save() {
        const date = Reminders.fromFields(dateField.text, timeField.text)
        if (!date) {
            error = qsTr("Enter the date as YYYY-MM-DD and the time as HH:MM.")
            return
        }
        if (date.getTime() <= Date.now()) {
            error = qsTr("Choose a time in the future.")
            return
        }
        error = ""
        saveRequested(Math.floor(date.getTime() / 1000), repeatBox.currentValue)
        close()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(340, (parent ? parent.width : 340) - 16)
    modal: true
    focus: true
    padding: 16
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        radius: 12
        color: editor.theme ? editor.theme.surface : "#ffffff"
        border.width: 1
        border.color: editor.theme ? editor.theme.border : "#e2e8f0"
    }

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            AppIcon {
                name: "bell"
                size: 16
                color: editor.theme ? editor.theme.accent : "#6366f1"
            }
            Label {
                text: editor.hasReminder ? qsTr("Edit reminder") : qsTr("Add reminder")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: editor.theme ? editor.theme.textPrimary : "#0f172a"
                Layout.fillWidth: true
            }
        }
        Label {
            text: editor.noteTitle.trim().length ? editor.noteTitle : qsTr("Untitled note")
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.pixelSize: 12
            color: editor.theme ? editor.theme.textSecondary : "#64748b"
            Layout.fillWidth: true
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: editor.visible ? Reminders.presets() : []
                delegate: StyledButton {
                    required property var modelData
                    objectName: "reminderPreset"
                    theme: editor.theme
                    text: modelData.label
                    font.pixelSize: 12
                    implicitHeight: 28
                    onClicked: editor.choose(modelData.date)
                }
            }
        }

        RowLayout {
            spacing: 8
            Layout.fillWidth: true
            StyledTextField {
                id: dateField
                objectName: "reminderDate"
                theme: editor.theme
                placeholderText: "YYYY-MM-DD"
                inputMethodHints: Qt.ImhDate
                Accessible.name: qsTr("Reminder date")
                Layout.fillWidth: true
                onAccepted: editor.save()
            }
            StyledTextField {
                id: timeField
                objectName: "reminderTime"
                theme: editor.theme
                placeholderText: "HH:MM"
                inputMethodHints: Qt.ImhTime
                Accessible.name: qsTr("Reminder time")
                Layout.preferredWidth: 84
                onAccepted: editor.save()
            }
        }

        ComboBox {
            id: repeatBox
            objectName: "reminderRepeat"
            Layout.fillWidth: true
            textRole: "text"
            valueRole: "value"
            Accessible.name: qsTr("Repeat")
            model: [
                { value: "none", text: qsTr("Does not repeat") },
                { value: "daily", text: qsTr("Every day") },
                { value: "weekly", text: qsTr("Every week") },
                { value: "monthly", text: qsTr("Every month (30 days)") }
            ]
        }

        Label {
            visible: editor.error.length > 0
            text: editor.error
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: editor.theme ? editor.theme.danger : "#ef4444"
            Layout.fillWidth: true
            Accessible.role: Accessible.AlertMessage
        }

        RowLayout {
            spacing: 6
            Layout.fillWidth: true
            Layout.topMargin: 4
            StyledButton {
                objectName: "reminderRemove"
                visible: editor.hasReminder
                theme: editor.theme
                variant: "ghost"
                text: qsTr("Remove")
                onClicked: {
                    editor.removeRequested()
                    editor.close()
                }
            }
            Item { Layout.fillWidth: true }
            StyledButton {
                theme: editor.theme
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: editor.close()
            }
            StyledButton {
                objectName: "reminderSave"
                theme: editor.theme
                variant: "accent"
                text: qsTr("Save")
                onClicked: editor.save()
            }
        }
    }
}
