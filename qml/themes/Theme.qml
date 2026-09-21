import QtQuick

QtObject {
    id: theme

    property string themeMode: "system"
    // "#rrggbb"; the rest of the accent family is derived from it.
    property color accentColor: "#6366f1"
    readonly property bool isDark: {
        if (themeMode === "dark" || themeMode === "black") return true
        if (themeMode === "light" || themeMode === "sepia") return false
        return Application.styleHints.colorScheme === Qt.ColorScheme.Dark
    }
    readonly property bool isSepia: themeMode === "sepia"
    readonly property bool isBlack: themeMode === "black"

    // Picks the colour for the current theme: light, dark, and optional
    // sepia and black variants that otherwise follow light and dark.
    function pick(light, dark, sepia, black) {
        if (isSepia && sepia !== undefined) return sepia
        if (isBlack && black !== undefined) return black
        return isDark ? dark : light
    }

    // Mixes a colour toward another by amount (0..1).
    function mix(from, to, amount) {
        const a = Qt.color(from), b = Qt.color(to)
        return Qt.rgba(a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount, a.b + (b.b - a.b) * amount, 1)
    }

    // Core Canvas & Surface
    readonly property color windowBackground: pick("#f8fafc", "#18181b", "#f4ecd8", "#000000")
    readonly property color surface: pick("#ffffff", "#27272a", "#fbf6ea", "#0c0c0e")
    readonly property color surfaceElevated: pick("#f8fafc", "#202024", "#f6efdd", "#08080a")
    readonly property color surfaceHover: pick("#f1f5f9", "#3f3f46", "#ece2c9", "#1c1c20")
    readonly property color surfaceActive: pick("#e2e8f0", "#52525b", "#e2d5b6", "#2a2a30")
    readonly property color border: pick("#e2e8f0", "#3f3f46", "#e0d3b3", "#232328")
    readonly property color borderSubtle: pick("#f1f5f9", "#27272a", "#eee4cc", "#141417")

    // Typography
    readonly property color textPrimary: pick("#0f172a", "#f4f4f5", "#3b2f22", "#f4f4f5")
    readonly property color textSecondary: pick("#64748b", "#a1a1aa", "#7a6650", "#a1a1aa")
    readonly property color textMuted: pick("#94a3b8", "#71717a", "#a08c72", "#71717a")

    // Brand / Accent
    readonly property color accent: accentColor
    readonly property color accentHover: Qt.darker(accentColor, 1.12)
    readonly property color accentActive: Qt.darker(accentColor, 1.25)
    readonly property color accentText: "#ffffff"
    readonly property color accentSubtle: isDark ? mix(accentColor, "#000000", 0.62) : mix(accentColor, "#ffffff", 0.85)
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
