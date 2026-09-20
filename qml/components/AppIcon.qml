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
        "search": "M11 3a8 8 0 1 0 0 16 8 8 0 0 0 0-16z m21 21-4.3-4.3"
    })

    Item {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: root.size / 24.0
        transformOrigin: Item.Center

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeColor: root.color
                strokeWidth: root.strokeWidth
                fillColor: root.filled ? root.color : "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathSvg {
                    path: root.iconPaths[root.name] || ""
                }
            }
        }
    }
}
