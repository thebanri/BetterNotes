import QtQuick
import QtQuick.Controls
import "../themes"

// Small pill label used for priority, state and tag markers in the library.
Label {
    id: pill

    property Theme theme: null
    property color textColor: theme ? theme.textSecondary : "#64748b"
    property color fillColor: theme ? theme.surfaceHover : "#f1f5f9"

    font.pixelSize: 10
    font.weight: Font.DemiBold
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: textColor
    topPadding: 2
    bottomPadding: 2
    leftPadding: 7
    rightPadding: 7

    background: Rectangle {
        radius: height / 2
        color: pill.fillColor
    }
}
