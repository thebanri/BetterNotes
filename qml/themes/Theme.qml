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
