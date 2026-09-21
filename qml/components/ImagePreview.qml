import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../themes"

// A note's image at full size in a window of its own; GIFs play. The window
// fits the screen, and a larger image is scaled down to fit.
Window {
    id: preview

    property Theme theme: null
    property url source: ""
    property string name: ""

    function show(url, fileName) {
        source = url
        name = fileName
        const area = screen ? Qt.size(screen.desktopAvailableWidth, screen.desktopAvailableHeight) : Qt.size(1280, 800)
        const natural = image.sourceSize
        width = Math.max(320, Math.min(natural.width + 32, area.width * 0.85))
        height = Math.max(240, Math.min(natural.height + 72, area.height * 0.85))
        visible = true
        raise()
        requestActivate()
    }

    title: name.length ? name : qsTr("Image")
    color: theme ? theme.windowBackground : "#18181b"
    flags: Qt.Dialog

    Shortcut { sequences: [StandardKey.Close, "Escape"]; onActivated: preview.close() }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        AnimatedImage {
            id: image
            objectName: "previewImage"
            source: preview.source
            fillMode: Image.PreserveAspectFit
            // Never upscale a small image past its own size.
            Layout.maximumWidth: sourceSize.width
            Layout.maximumHeight: sourceSize.height
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignCenter
            smooth: true
            mipmap: true
        }

        Label {
            text: image.status === Image.Ready
                ? qsTr("%1 × %2 px").arg(image.sourceSize.width).arg(image.sourceSize.height)
                : (image.status === Image.Error ? qsTr("The image could not be shown.") : "")
            color: preview.theme ? preview.theme.textSecondary : "#a1a1aa"
            font.pixelSize: 12
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
