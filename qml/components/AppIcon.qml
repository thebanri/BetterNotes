import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property string name: "settings"
    property color color: "#ffffff"
    property real size: 16
    property real strokeWidth: 2.0
    property bool filled: false

    implicitWidth: size
    implicitHeight: size

    readonly property var iconPaths: ({
        "pin": "M12 17v5 M5 17h14v-1.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V6h1a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4h1v4.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24Z",
        "pin-off": "m2 2 20 20 M8.61 3H16a2 2 0 0 1 2 2v1a2 2 0 0 0 2 2h0a2 2 0 0 1 2 2v2.34a2 2 0 0 1-.59 1.42l-1.8 1.8 M15 10.76V6 M5.88 5.88A2 2 0 0 0 5 7.64V9a2 2 0 0 1-.59 1.41l-1.8 1.8A2 2 0 0 0 2 13.64V15a2 2 0 0 0 2 2h11 M12 17v5",
        "settings": "M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z",
        "sliders": "M4 21v-7 M4 10V3 M12 21v-9 M12 8V3 M20 21v-5 M20 12V3 M1 14h6 M9 8h6 M17 16h6",
        "plus": "M5 12h14 M12 5v14",
        "minus": "M5 12h14",
        "chevron-down": "m6 9 6 6 6-6",
        "chevron-up": "m18 15-6-6-6 6",
        "x": "M18 6 6 18 M6 6l12 12",
        "copy": "M10 8h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2V10a2 2 0 0 1 2-2z M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2",
        "trash": "M3 6h18 M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6 M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2 M10 11v6 M14 11v6",
        "palette": "M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z",
        "library": "m16 6 4 14 M12 6v14 M8 8v12 M4 4v16",
        "clock": "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20z M12 6v6l4 2",
        "check": "m20 6-11 11-5-5",
        "maximize": "M15 3h6v6 M9 21H3v-6 M21 3l-7 7 M3 21l7-7",
        "minimize": "M4 14h6v6 M20 10h-6V4 M14 10l7-7 M3 21l7-7",
        "search": "M11 3a8 8 0 1 0 0 16 8 8 0 0 0 0-16z M21 21l-4.3-4.3",
        "bold": "M6 4h8a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z M6 12h9a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z",
        "italic": "M19 4h-9 M14 20H5 M15 4L9 20",
        "underline": "M6 4v6a6 6 0 0 0 12 0V4 M4 20h16",
        "type": "M4 7V4h16v3 M9 20h6 M12 4v16",
        "heading-1": "M4 12h8 M4 18V6 M12 18V6 M17 12l3-2v8",
        "heading-2": "M4 12h8 M4 18V6 M12 18V6 M21 18h-4c0-4 4-3 4-6 0-1.5-1-2.5-2.5-2.5-1.5 0-2.5 1-2.5 2.5",
        "image": "M21 19V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2z M8.5 10a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z M21 15l-5-5L5 21",
        "droplet": "M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z",
        "archive": "M3 3h18v5H3z M5 8v11a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8 M10 12h4",
        "archive-restore": "M3 3h18v5H3z M5 8v11a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8 M12 17v-6 M9.5 13.5 12 11l2.5 2.5",
        "locate": "M2 12h3 M19 12h3 M12 2v3 M12 19v3 M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10z",
        "eye": "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z",
        "eye-off": "M2 2l20 20 M6.7 6.7C4 8.5 2 12 2 12s3.5 7 10 7c2 0 3.8-.7 5.3-1.7 M10 5.2c.6-.1 1.3-.2 2-.2 6.5 0 10 7 10 7s-.8 1.6-2.3 3.3 M14.1 14.1a3 3 0 0 1-4.2-4.2",
        "sun": "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z M12 2v2 M12 20v2 M4.93 4.93l1.41 1.41 M17.66 17.66l1.41 1.41 M2 12h2 M20 12h2 M6.34 17.66l-1.41 1.41 M19.07 4.93l-1.41 1.41",
        "moon": "M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9z",
        "monitor": "M4 4h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M8 21h8 M12 17v4",
        "sticky-note": "M16 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V8z M15 3v4a2 2 0 0 0 2 2h4",
        "tag": "M12.6 2.6A2 2 0 0 0 11.2 2H4a2 2 0 0 0-2 2v7.2a2 2 0 0 0 .6 1.4l8.7 8.7a2.4 2.4 0 0 0 3.4 0l6.6-6.6a2.4 2.4 0 0 0 0-3.4z M7.5 6.5a1 1 0 1 0 0 2 1 1 0 0 0 0-2z",
        "more": "M12 11a1 1 0 1 0 0 2 1 1 0 0 0 0-2z M12 4a1 1 0 1 0 0 2 1 1 0 0 0 0-2z M12 18a1 1 0 1 0 0 2 1 1 0 0 0 0-2z",
        "bell": "M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9 M10.3 21a1.94 1.94 0 0 0 3.4 0",
        "square": "M5 4h14a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z"
    })

    // Window-control glyphs are drawn with whole-pixel rectangles: a stroked
    // path this small lands between pixels and its edges fade.
    readonly property bool windowGlyph: name === "window-maximize" || name === "window-restore"
    readonly property int glyphLine: Math.max(1, Math.round(strokeWidth * size / 24))
    readonly property int glyphBox: Math.round(size * (name === "window-restore" ? 0.58 : 0.7))

    Item {
        visible: root.windowGlyph
        anchors.centerIn: parent
        width: Math.round(root.size)
        height: Math.round(root.size)

        // Back window of the restore glyph: its top and right edges only.
        Rectangle {
            visible: root.name === "window-restore"
            x: Math.round((parent.width - root.glyphBox) / 2) + Math.round(root.size * 0.14)
            y: Math.round((parent.height - root.glyphBox) / 2) - Math.round(root.size * 0.14)
            width: root.glyphBox
            height: root.glyphLine
            color: root.color
        }
        Rectangle {
            visible: root.name === "window-restore"
            x: Math.round((parent.width - root.glyphBox) / 2) + Math.round(root.size * 0.14) + root.glyphBox - root.glyphLine
            y: Math.round((parent.height - root.glyphBox) / 2) - Math.round(root.size * 0.14)
            width: root.glyphLine
            height: root.glyphBox
            color: root.color
        }
        Rectangle {
            x: Math.round((parent.width - root.glyphBox) / 2)
            y: Math.round((parent.height - root.glyphBox) / 2)
            width: root.glyphBox
            height: root.glyphBox
            radius: Math.min(2, root.glyphLine + 1)
            color: "transparent"
            border.width: root.glyphLine
            border.color: root.color
        }
    }

    // The path is scaled rather than the item, so the antialiasing layer is
    // rendered at the icon's real size instead of being shrunk from 24px.
    Shape {
        visible: !root.windowGlyph
        anchors.centerIn: parent
        width: root.size
        height: root.size
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            scale: Qt.size(root.size / 24.0, root.size / 24.0)
            strokeColor: root.color
            strokeWidth: root.strokeWidth * root.size / 24.0
            fillColor: root.filled ? root.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.iconPaths[root.name] || ""
            }
        }
    }
}
