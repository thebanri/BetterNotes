use betternotes_core::desktop::{DesktopEnvironment, DesktopReport, DisplayServer};

#[test]
fn display_server_and_positioning_policy() {
    assert!(DisplayServer::X11.can_position_windows());
    assert!(DisplayServer::Offscreen.can_position_windows());
    assert!(!DisplayServer::Wayland.can_position_windows());
    assert!(!DisplayServer::Unknown.can_position_windows());

    assert_eq!(DisplayServer::Wayland.name(), "Wayland");
    assert_eq!(DisplayServer::X11.name(), "X11");
}

#[test]
fn desktop_environments_classification_and_hints() {
    let hyprland = DesktopEnvironment::Hyprland;
    assert!(hyprland.is_tiling());
    assert!(hyprland.window_rule_hint().unwrap().contains("float"));
    assert!(hyprland.tray_notes().contains("Waybar"));

    let sway = DesktopEnvironment::Sway;
    assert!(sway.is_tiling());
    assert!(sway.window_rule_hint().unwrap().contains("floating enable"));

    let kde = DesktopEnvironment::KdePlasma;
    assert!(!kde.is_tiling());
    assert!(kde.window_rule_hint().is_none());
    assert!(kde.tray_notes().contains("StatusNotifierItem"));

    let gnome = DesktopEnvironment::Gnome;
    assert!(!gnome.is_tiling());
    assert!(gnome.tray_notes().contains("AppIndicator"));

    let xfce = DesktopEnvironment::Xfce;
    assert!(!xfce.is_tiling());

    let cinnamon = DesktopEnvironment::Cinnamon;
    assert!(!cinnamon.is_tiling());

    let mate = DesktopEnvironment::Mate;
    assert!(!mate.is_tiling());

    let budgie = DesktopEnvironment::Budgie;
    assert!(!budgie.is_tiling());
}

#[test]
fn desktop_report_generation() {
    let report = DesktopReport {
        display_server: DisplayServer::Wayland,
        desktop: DesktopEnvironment::Hyprland,
    };
    let text = report.format_report();
    assert!(text.contains("Wayland"));
    assert!(text.contains("Hyprland"));
    assert!(text.contains("Compositor-Managed"));
    assert!(text.contains("windowrule = float"));
}
