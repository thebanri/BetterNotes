pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../themes"

// Asks for the master password of locked notes: to set it up, to unlock, or
// to change it. The owner checks the password and reports errors back.
Popup {
    id: dialog

    property Theme theme: null
    // "setup", "unlock" or "change".
    property string mode: "unlock"
    property string error: ""
    // Shown under the title, e.g. which note is being opened.
    property string subject: ""

    // password: the password to set or unlock with, or the current one when
    // changing; replacement: the new password when changing.
    signal submitted(string password, string replacement)

    function openAs(newMode, newSubject) {
        mode = newMode
        subject = newSubject || ""
        error = ""
        first.text = ""
        second.text = ""
        third.text = ""
        open()
        first.forceActiveFocus()
    }

    function submit() {
        if (mode === "setup" || mode === "change") {
            const chosen = mode === "setup" ? first.text : second.text
            const repeated = mode === "setup" ? second.text : third.text
            if (chosen.length < 8) {
                error = qsTr("Use at least 8 characters.")
                return
            }
            if (chosen !== repeated) {
                error = qsTr("The passwords do not match.")
                return
            }
            submitted(first.text, mode === "change" ? second.text : "")
            return
        }
        submitted(first.text, "")
    }

    component PasswordField: TextField {
        echoMode: TextInput.Password
        passwordCharacter: "•"
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        selectByMouse: true
        Layout.fillWidth: true
        onAccepted: dialog.submit()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(360, (parent ? parent.width : 360) - 24)
    modal: true
    focus: true
    padding: 18
    closePolicy: Popup.CloseOnEscape
    onClosed: {
        // Do not keep typed passwords around in the fields.
        first.text = ""
        second.text = ""
        third.text = ""
    }

    background: Rectangle {
        radius: 12
        color: dialog.theme ? dialog.theme.surface : "#ffffff"
        border.width: 1
        border.color: dialog.theme ? dialog.theme.border : "#e2e8f0"
    }

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            spacing: 8
            AppIcon {
                name: "lock"
                size: 16
                color: dialog.theme ? dialog.theme.accent : "#6366f1"
            }
            Label {
                text: dialog.mode === "setup" ? qsTr("Set a password for locked notes")
                    : dialog.mode === "change" ? qsTr("Change the password")
                    : qsTr("Unlock locked notes")
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: dialog.theme ? dialog.theme.textPrimary : "#0f172a"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
        Label {
            visible: dialog.subject.length > 0
            text: dialog.subject
            textFormat: Text.PlainText
            elide: Text.ElideRight
            font.pixelSize: 12
            color: dialog.theme ? dialog.theme.textSecondary : "#64748b"
            Layout.fillWidth: true
        }
        Label {
            visible: dialog.mode === "setup"
            text: qsTr("Locked notes are encrypted with this password. It cannot be recovered: if you forget it, the locked notes cannot be opened again. Their titles, attached files and images are not encrypted.")
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: dialog.theme ? dialog.theme.warning : "#b45309"
            Layout.fillWidth: true
        }

        PasswordField {
            id: first
            objectName: "passwordFirst"
            placeholderText: dialog.mode === "change" ? qsTr("Current password") : qsTr("Password")
        }
        PasswordField {
            id: second
            objectName: "passwordSecond"
            visible: dialog.mode !== "unlock"
            placeholderText: dialog.mode === "change" ? qsTr("New password") : qsTr("Repeat the password")
        }
        PasswordField {
            id: third
            objectName: "passwordThird"
            visible: dialog.mode === "change"
            placeholderText: qsTr("Repeat the new password")
        }

        Label {
            visible: dialog.error.length > 0
            text: dialog.error
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: dialog.theme ? dialog.theme.danger : "#ef4444"
            Layout.fillWidth: true
            Accessible.role: Accessible.AlertMessage
        }

        RowLayout {
            spacing: 6
            Layout.topMargin: 4
            Item { Layout.fillWidth: true }
            StyledButton {
                theme: dialog.theme
                variant: "ghost"
                text: qsTr("Cancel")
                onClicked: dialog.close()
            }
            StyledButton {
                objectName: "passwordSubmit"
                theme: dialog.theme
                variant: "accent"
                text: dialog.mode === "unlock" ? qsTr("Unlock") : qsTr("Save")
                onClicked: dialog.submit()
            }
        }
    }
}
