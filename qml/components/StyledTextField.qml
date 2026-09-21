import QtQuick
import QtQuick.Templates as T
import "../themes"

T.TextField {
    id: control

    property Theme theme: null

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding)

    padding: 6
    leftPadding: 10
    rightPadding: 10

    color: control.theme ? control.theme.textPrimary : control.palette.text
    placeholderTextColor: control.theme ? control.theme.textMuted : control.palette.placeholderText
    selectedTextColor: control.theme ? control.theme.accentText : control.palette.highlightedText
    selectionColor: control.theme ? control.theme.accent : control.palette.highlight
    verticalAlignment: TextInput.AlignVCenter

    // The template draws no placeholder of its own.
    Text {
        x: control.leftPadding
        y: control.topPadding
        width: control.width - control.leftPadding - control.rightPadding
        height: control.height - control.topPadding - control.bottomPadding
        text: control.placeholderText
        font: control.font
        color: control.placeholderTextColor
        verticalAlignment: control.verticalAlignment
        elide: Text.ElideRight
        visible: control.length === 0 && control.preeditText.length === 0
        Accessible.ignored: true
    }

    background: Rectangle {
        implicitWidth: 160
        implicitHeight: 32
        radius: control.theme ? control.theme.radiusSm : 4
        color: control.theme ? control.theme.surface : "#ffffff"
        border.width: control.activeFocus ? 2 : 1
        border.color: {
            if (control.activeFocus) return control.theme ? control.theme.accent : "#6366f1"
            return control.theme ? control.theme.border : "#d1d5db"
        }

        Behavior on border.color {
            ColorAnimation { duration: control.theme ? control.theme.animShort : 100 }
        }
    }
}
