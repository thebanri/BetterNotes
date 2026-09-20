import QtQuick
import QtQuick.Templates as T
import "../themes"

T.Button {
    id: control

    property string variant: "default"
    property Theme theme: null

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    padding: 6
    leftPadding: 12
    rightPadding: 12
    spacing: 6

    contentItem: Text {
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
    }

    background: Rectangle {
        implicitWidth: 72
        implicitHeight: 32
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
