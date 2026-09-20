//! Linux global shortcuts abstraction and compositor documentation.

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShortcutDefinition {
    pub name: &'static str,
    pub description: &'static str,
    pub default_sequence: &'static str,
    pub command_arg: &'static str,
}

pub struct GlobalShortcutService;

impl GlobalShortcutService {
    pub const SHORTCUTS: &'static [ShortcutDefinition] = &[
        ShortcutDefinition {
            name: "quick_capture",
            description: "Open floating Quick Capture window",
            default_sequence: "Ctrl+Alt+Space",
            command_arg: "--quick-capture",
        },
        ShortcutDefinition {
            name: "search_notes",
            description: "Open BetterNotes Search / Command Palette",
            default_sequence: "Ctrl+Alt+K",
            command_arg: "--search",
        },
    ];

    /// Reports whether the current display server permits direct application-level global grabs.
    pub fn can_grab_directly(platform: &str) -> bool {
        matches!(platform, "xcb" | "x11")
    }

    /// Provides sample compositor configuration instructions for Wayland users.
    pub fn compositor_config_hint(compositor: &str) -> &'static str {
        match compositor.to_lowercase().as_str() {
            "hyprland" => "bind = $mainMod ALT, Space, exec, betternotes --quick-capture",
            "sway" => "bindsym $mod+Mod1+space exec betternotes --quick-capture",
            "kde" | "plasma" => "Configure in System Settings -> Shortcuts -> Custom Shortcuts",
            "gnome" => "Configure in Settings -> Keyboard -> Custom Shortcuts",
            _ => "Bind your preferred key to `betternotes --quick-capture` in your window manager.",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shortcut_platform_capabilities_and_hints() {
        assert!(GlobalShortcutService::can_grab_directly("xcb"));
        assert!(GlobalShortcutService::can_grab_directly("x11"));
        assert!(!GlobalShortcutService::can_grab_directly("wayland"));
        assert!(!GlobalShortcutService::can_grab_directly("wayland-egl"));
        assert!(!GlobalShortcutService::can_grab_directly("offscreen"));

        assert!(GlobalShortcutService::compositor_config_hint("hyprland").contains("quick-capture"));
        assert_eq!(GlobalShortcutService::SHORTCUTS.len(), 2);
    }
}
