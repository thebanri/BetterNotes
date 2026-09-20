import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BetterNotes.App

ApplicationWindow {
    id: window

    width: 640
    height: 420
    minimumWidth: 360
    minimumHeight: 280
    visible: true
    title: applicationInfo.name()

    ApplicationInfo {
        id: applicationInfo
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 440)
        spacing: 16

        Label {
            text: applicationInfo.name()
            font.pixelSize: 30
            font.bold: true
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            text: qsTr("A quiet place for your ideas.")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            text: qsTr("Foundation preview · %1").arg(applicationInfo.version())
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Button {
            text: qsTr("Close")
            Layout.alignment: Qt.AlignHCenter
            onClicked: window.close()
        }
    }

    Shortcut {
        sequence: StandardKey.Quit
        onActivated: window.close()
    }
}
