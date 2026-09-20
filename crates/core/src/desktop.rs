//! Desktop environment and display server capability detection for Linux desktop integration.

use std::env;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DisplayServer {
    Wayland,
    X11,
    Offscreen,
    Unknown,
}

impl DisplayServer {
    pub fn detect() -> Self {
        if let Ok(platform) = env::var("QT_QPA_PLATFORM") {
            if platform == "offscreen" {
                return Self::Offscreen;
            }
            if platform.starts_with("wayland") {
                return Self::Wayland;
            }
            if platform == "xcb" {
                return Self::X11;
            }
        }
        if env::var_os("WAYLAND_DISPLAY").is_some() {
            Self::Wayland
        } else if env::var_os("DISPLAY").is_some() {
            Self::X11
        } else {
            Self::Unknown
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Wayland => "Wayland",
            Self::X11 => "X11",
            Self::Offscreen => "Offscreen (Headless)",
            Self::Unknown => "Unknown",
        }
    }

    pub fn can_position_windows(&self) -> bool {
        // Wayland intentionally prohibits clients from setting absolute screen coordinates.
        // X11 and offscreen testing support explicit geometry positioning.
        matches!(self, Self::X11 | Self::Offscreen)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DesktopEnvironment {
    KdePlasma,
    Gnome,
    Xfce,
    Cinnamon,
    Mate,
    Budgie,
    Hyprland,
    Sway,
    Other(String),
}

impl DesktopEnvironment {
    pub fn detect() -> Self {
        if env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
            return Self::Hyprland;
        }
        if env::var_os("SWAYSOCK").is_some() {
            return Self::Sway;
        }

        let desktop = env::var("XDG_CURRENT_DESKTOP")
            .or_else(|_| env::var("DESKTOP_SESSION"))
            .unwrap_or_default()
            .to_uppercase();

        if desktop.contains("KDE") || desktop.contains("PLASMA") {
            Self::KdePlasma
        } else if desktop.contains("GNOME") {
            Self::Gnome
        } else if desktop.contains("XFCE") {
            Self::Xfce
        } else if desktop.contains("CINNAMON") {
            Self::Cinnamon
        } else if desktop.contains("MATE") {
            Self::Mate
        } else if desktop.contains("BUDGIE") {
            Self::Budgie
        } else if desktop.contains("HYPRLAND") {
            Self::Hyprland
        } else if desktop.contains("SWAY") {
            Self::Sway
        } else if !desktop.is_empty() {
            Self::Other(desktop)
        } else {
            Self::Other("Generic / Standalone WM".into())
        }
    }

    pub fn name(&self) -> &str {
        match self {
            Self::KdePlasma => "KDE Plasma",
            Self::Gnome => "GNOME",
            Self::Xfce => "XFCE",
            Self::Cinnamon => "Cinnamon",
            Self::Mate => "MATE",
            Self::Budgie => "Budgie",
            Self::Hyprland => "Hyprland",
            Self::Sway => "Sway",
            Self::Other(name) => name.as_str(),
        }
    }

    pub fn is_tiling(&self) -> bool {
        matches!(self, Self::Hyprland | Self::Sway)
    }

    pub fn window_rule_hint(&self) -> Option<&'static str> {
        match self {
            Self::Hyprland => Some(
                "windowrule = float, ^(betternotes)$\nwindowrule = size 380 360, ^(betternotes)$",
            ),
            Self::Sway => Some("for_window [app_id=\"betternotes\"] floating enable"),
            _ => None,
        }
    }

    pub fn tray_notes(&self) -> &'static str {
        match self {
            Self::Gnome => {
                "GNOME requires the 'AppIndicator and KStatusNotifierItem Support' extension for tray icons."
            }
            Self::Hyprland | Self::Sway => {
                "Requires a status bar with SNI tray support (e.g. Waybar with 'tray' module enabled)."
            }
            _ => "StatusNotifierItem (Freedesktop SNI) supported natively.",
        }
    }
}

pub struct DesktopReport {
    pub display_server: DisplayServer,
    pub desktop: DesktopEnvironment,
}

impl DesktopReport {
    pub fn current() -> Self {
        Self {
            display_server: DisplayServer::detect(),
            desktop: DesktopEnvironment::detect(),
        }
    }

    pub fn format_report(&self) -> String {
        let mut out = String::new();
        out.push_str(
            "BetterNotes Platform & Compositor Diagnostics\n==============================================\n",
        );
        out.push_str(&format!(
            "Display Server:         {}\n",
            self.display_server.name()
        ));
        out.push_str(&format!(
            "Desktop Environment:    {}\n",
            self.desktop.name()
        ));
        out.push_str(&format!(
            "Window Positioning:     {}\n",
            if self.display_server.can_position_windows() {
                "Supported (Absolute X11/XCB coordinates)"
            } else {
                "Compositor-Managed (Wayland xdg-shell standard)"
            }
        ));
        out.push_str("Always-on-top:          Supported via Qt.WindowStaysOnTopHint\n");
        out.push_str(&format!(
            "System Tray:            {}\n",
            self.desktop.tray_notes()
        ));

        if let Some(rule) = self.desktop.window_rule_hint() {
            out.push_str(&format!(
                "\nTiling Compositor Rule Hint:\n-----------------------------\n{}\n",
                rule
            ));
        }

        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_server_and_desktop_detection_does_not_panic() {
        let server = DisplayServer::detect();
        assert!(!server.name().is_empty());
        let desktop = DesktopEnvironment::detect();
        assert!(!desktop.name().is_empty());

        let report = DesktopReport::current();
        let formatted = report.format_report();
        assert!(formatted.contains("BetterNotes Platform & Compositor Diagnostics"));
        assert!(formatted.contains(server.name()));
        assert!(formatted.contains(desktop.name()));
    }

    #[test]
    fn tiling_compositor_hints() {
        assert!(DesktopEnvironment::Hyprland.is_tiling());
        assert!(DesktopEnvironment::Sway.is_tiling());
        assert!(!DesktopEnvironment::KdePlasma.is_tiling());
        assert!(!DesktopEnvironment::Gnome.is_tiling());

        assert!(DesktopEnvironment::Hyprland
            .window_rule_hint()
            .unwrap()
            .contains("float"));
        assert!(DesktopEnvironment::Sway
            .window_rule_hint()
            .unwrap()
            .contains("floating enable"));
        assert!(DesktopEnvironment::KdePlasma.window_rule_hint().is_none());
    }
}
