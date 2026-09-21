import QtQuick

QtObject {
    id: theme

    property string themeMode: "system"
    readonly property bool isDark: {
        if (themeMode === "dark") return true
        if (themeMode === "light") return false
        return Application.styleHints.colorScheme === Qt.ColorScheme.Dark
    }

    // Core Canvas & Surface
    readonly property color windowBackground: isDark ? "#18181b" : "#f8fafc"
    readonly property color surface: isDark ? "#27272a" : "#ffffff"
    readonly property color surfaceElevated: isDark ? "#202024" : "#f8fafc"
    readonly property color surfaceHover: isDark ? "#3f3f46" : "#f1f5f9"
    readonly property color surfaceActive: isDark ? "#52525b" : "#e2e8f0"
    readonly property color border: isDark ? "#3f3f46" : "#e2e8f0"
    readonly property color borderSubtle: isDark ? "#27272a" : "#f1f5f9"

    // Typography
    readonly property color textPrimary: isDark ? "#f4f4f5" : "#0f172a"
    readonly property color textSecondary: isDark ? "#a1a1aa" : "#64748b"
    readonly property color textMuted: isDark ? "#71717a" : "#94a3b8"

    // Brand / Accent
    readonly property color accent: "#6366f1"
    readonly property color accentHover: "#4f46e5"
    readonly property color accentActive: "#4338ca"
    readonly property color accentText: "#ffffff"
    readonly property color accentSubtle: isDark ? "#312e81" : "#e0e7ff"
    // Links in note text: blue that stays readable on the tinted note colours.
    readonly property color link: isDark ? "#8ab4ff" : "#1d4ed8"

    // Feedback
    readonly property color danger: "#ef4444"
    readonly property color dangerHover: "#dc2626"
    readonly property color dangerText: "#ffffff"
    readonly property color dangerSubtle: isDark ? "#450a0a" : "#fee2e2"
    readonly property color warning: "#f59e0b"
    readonly property color warningSubtle: isDark ? "#451a03" : "#fef3c7"
    readonly property color success: "#22c55e"

    // Sticky Note Tones (Warm Amber/Yellow modern pastel)
    readonly property color noteBackground: isDark ? "#23201d" : "#fefce8"
    readonly property color noteHeader: isDark ? "#2c2824" : "#fef9c3"
    readonly property color noteBorder: isDark ? "#443c34" : "#fde047"
    readonly property color noteText: isDark ? "#f5f5f4" : "#1c1917"
    readonly property color noteTextSecondary: isDark ? "#a8a29e" : "#78716c"

    // Sticky note colours, shared by the note windows and the library cards.
    // A note's colour is a preset name or a custom "#rrggbb"; each yields a
    // background, a header and a border tone for the current light/dark mode.
    readonly property var tintPalettes: ({
        "yellow": {
            bg: isDark ? "#28231a" : "#fefce8",
            header: isDark ? "#362f23" : "#fef08a",
            border: isDark ? "#4f4230" : "#fde047"
        },
        "green": {
            bg: isDark ? "#17271c" : "#f0fdf4",
            header: isDark ? "#1e3727" : "#dcfce7",
            border: isDark ? "#2e573c" : "#86efac"
        },
        "pink": {
            bg: isDark ? "#2d161d" : "#fff1f2",
            header: isDark ? "#3d1c26" : "#ffe4e6",
            border: isDark ? "#5c2738" : "#fda4af"
        },
        "blue": {
            bg: isDark ? "#142436" : "#f0f9ff",
            header: isDark ? "#1a324b" : "#e0f2fe",
            border: isDark ? "#254e77" : "#7dd3fc"
        },
        "purple": {
            bg: isDark ? "#241834" : "#faf5ff",
            header: isDark ? "#32204a" : "#f3e8ff",
            border: isDark ? "#4c2f70" : "#d8b4fe"
        }
    })

    function customTint(colorHex, role) {
        let base = Qt.color(colorHex)
        if (!base || base === "transparent") return noteBackground
        if (isDark) {
            if (role === "bg") return Qt.rgba(base.r * 0.18 + 0.04, base.g * 0.18 + 0.04, base.b * 0.18 + 0.04, 1.0)
            if (role === "header") return Qt.rgba(base.r * 0.28 + 0.06, base.g * 0.28 + 0.06, base.b * 0.28 + 0.06, 1.0)
            return Qt.rgba(base.r * 0.45 + 0.1, base.g * 0.45 + 0.1, base.b * 0.45 + 0.1, 1.0)
        } else {
            if (role === "bg") return Qt.rgba(1.0 - (1.0 - base.r) * 0.10, 1.0 - (1.0 - base.g) * 0.10, 1.0 - (1.0 - base.b) * 0.10, 1.0)
            if (role === "header") return Qt.rgba(1.0 - (1.0 - base.r) * 0.22, 1.0 - (1.0 - base.g) * 0.22, 1.0 - (1.0 - base.b) * 0.22, 1.0)
            return Qt.rgba(1.0 - (1.0 - base.r) * 0.45, 1.0 - (1.0 - base.g) * 0.45, 1.0 - (1.0 - base.b) * 0.45, 1.0)
        }
    }

    function noteTint(name, role) {
        const preset = tintPalettes[name]
        if (preset) return preset[role]
        if (typeof name === "string" && name.startsWith("#")) return customTint(name, role)
        if (role === "header") return noteHeader
        if (role === "border") return noteBorder
        return noteBackground
    }

    // Geometry / Spacing
    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 12
    readonly property int spacingLg: 16
    readonly property int spacingXl: 24

    readonly property int radiusSm: 4
    readonly property int radiusMd: 8
    readonly property int radiusLg: 12
    readonly property int radiusFull: 9999

    // Animation Timers (keep fast and subtle)
    readonly property int animShort: 120
    readonly property int animMedium: 200
}
