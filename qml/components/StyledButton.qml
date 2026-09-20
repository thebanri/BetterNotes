import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import "../themes"

T.Button {
    id: control

    property string variant: "default"
    property Theme theme: null
    property string iconName: ""
    property real iconSize: 16
    property real iconStrokeWidth: 2.0
    property color iconColor: {
        if (!control.theme) return control.palette.buttonText
        if (control.variant === "accent") return control.theme.accentText
        if (control.variant === "danger") return control.theme.dangerText
        if (control.variant === "ghost") return control.hovered ? control.theme.textPrimary : control.theme.textSecondary
        return control.theme.textPrimary
    }

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    padding: 6
    leftPadding: (iconName.length > 0 && text.length === 0) ? padding : ((text.length > 0 && iconName.length === 0) ? Math.max(padding, 10) : padding)
    rightPadding: leftPadding
    spacing: 6

    contentItem: RowLayout {
        spacing: control.spacing
        Item { Layout.fillWidth: true; visible: control.text.length > 0 }
        AppIcon {
            name: control.iconName
            size: control.iconSize
            color: control.iconColor
            strokeWidth: control.iconStrokeWidth
            visible: control.iconName.length > 0
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
        }
        Text {
            text: control.text
            font: control.font
            opacity: control.enabled ? 1.0 : 0.4
            color: {
                if (!control.theme) return control.palette.buttonText
                if (control.variant === "accent") return control.theme.accentText
                if (control.variant === "danger") return control.theme.dangerText
                return control.theme.textPrimary
            }
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            visible: control.text.length > 0
            Layout.alignment: Qt.AlignVCenter
        }
        Item { Layout.fillWidth: true; visible: control.text.length > 0 }
    }

    background: Rectangle {
        implicitWidth: (control.iconName.length > 0 && control.text.length === 0) ? 26 : 72
        implicitHeight: (control.iconName.length > 0 && control.text.length === 0) ? 24 : 32
        radius: control.theme ? control.theme.radiusSm : 4
        opacity: control.enabled ? 1.0 : 0.5
        border.width: (control.variant === "ghost") ? 0 : 1
        border.color: {
            if (control.activeFocus) return control.theme ? control.theme.accent : "#6366f1"
            if (!control.theme) return "#d1d5db"
            if (control.variant === "accent") return control.theme.accentHover
            if (control.variant === "danger") return control.theme.dangerHover
            return control.theme.border
        }

        color: {
            if (!control.theme) return "#e5e7eb"
            if (control.variant === "accent") {
                return control.down ? control.theme.accentActive : (control.hovered ? control.theme.accentHover : control.theme.accent)
            }
            if (control.variant === "danger") {
                return control.down ? control.theme.dangerHover : (control.hovered ? control.theme.dangerHover : control.theme.danger)
            }
            if (control.variant === "ghost") {
                return control.down ? control.theme.surfaceActive : (control.hovered ? control.theme.surfaceHover : "transparent")
            }
            return control.down ? control.theme.surfaceActive : (control.hovered ? control.theme.surfaceHover : control.theme.surface)
        }

        Behavior on color {
            ColorAnimation { duration: control.theme ? control.theme.animShort : 100 }
        }
    }
}
