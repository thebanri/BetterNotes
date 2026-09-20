//! Qt platform capability policy; QML only supplies the active plugin name.

pub fn can_position_windows(plugin: &str) -> bool {
    // xcb includes XWayland. offscreen is useful for headless validation.
    // Wayland and unknown backends leave absolute placement to the compositor.
    matches!(plugin, "xcb" | "offscreen")
}
