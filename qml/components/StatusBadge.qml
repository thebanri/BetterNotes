import QtQuick
import QtQuick.Layouts
import "../themes"

Rectangle {
    id: badge

    property bool dirty: false
    property Theme theme: null

    implicitWidth: row.implicitWidth + 14
    implicitHeight: 22
    radius: theme ? theme.radiusFull : 11
    color: dirty ? (theme ? (theme.isDark ? "#3b2512" : "#fef3c7") : "#fef3c7")
                 : (theme ? (theme.isDark ? "#143322" : "#dcfce7") : "#dcfce7")
    border.width: 1
    border.color: dirty ? (theme ? (theme.isDark ? "#78350f" : "#fcd34d") : "#fcd34d")
                        : (theme ? (theme.isDark ? "#166534" : "#86efac") : "#86efac")

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Rectangle {
            Layout.preferredWidth: 6
            Layout.preferredHeight: 6
            radius: 3
            color: badge.dirty ? "#f59e0b" : (badge.theme ? badge.theme.success : "#22c55e")
        }

        Text {
            text: badge.dirty ? qsTr("Unsaved") : qsTr("Saved")
            font.pixelSize: 11
            font.weight: Font.Medium
            color: badge.dirty ? (badge.theme ? (badge.theme.isDark ? "#fde68a" : "#92400e") : "#92400e")
                               : (badge.theme ? (badge.theme.isDark ? "#bbf7d0" : "#166534") : "#166534")
        }
    }
}
