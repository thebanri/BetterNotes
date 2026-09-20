use betternotes_core::autostart::{is_autostart_enabled_at, set_autostart_at};
use betternotes_core::paths::{autostart_directory, config_directory};
use betternotes_core::{GlobalShortcutService, NotificationService};
use std::ffi::OsStr;
use std::fs;

#[test]
fn xdg_config_and_autostart_paths() {
    let custom_config = OsStr::new("/home/custom/.config");
    assert_eq!(
        config_directory(Some(custom_config), None).unwrap(),
        std::path::PathBuf::from("/home/custom/.config")
    );
    assert_eq!(
        autostart_directory(Some(custom_config), None).unwrap(),
        std::path::PathBuf::from("/home/custom/.config/autostart")
    );
}

#[test]
fn autostart_desktop_file_lifecycle() {
    let temp_dir = tempfile::tempdir().unwrap();
    let desktop_path = temp_dir.path().join("autostart/betternotes.desktop");

    // Initially not enabled
    assert!(!is_autostart_enabled_at(&desktop_path));

    // Enable autostart with custom exec
    set_autostart_at(&desktop_path, true, "betternotes").unwrap();
    assert!(desktop_path.exists());
    assert!(is_autostart_enabled_at(&desktop_path));

    let content = fs::read_to_string(&desktop_path).unwrap();
    assert!(content.contains("[Desktop Entry]"));
    assert!(content.contains("Type=Application"));
    assert!(content.contains("Name=BetterNotes"));
    assert!(content.contains("Exec=betternotes --background"));
    assert!(content.contains("X-GNOME-Autostart-enabled=true"));

    // Disable autostart
    set_autostart_at(&desktop_path, false, "betternotes").unwrap();
    assert!(!desktop_path.exists());
    assert!(!is_autostart_enabled_at(&desktop_path));
}

#[test]
fn notifications_and_shortcuts_graceful_handling() {
    // NotificationService should never panic, even if no daemon is listening
    let res = NotificationService::notify("Test Title", "Test Body");
    assert!(res.is_ok());

    // Shortcut service sanity checks
    assert!(!GlobalShortcutService::SHORTCUTS.is_empty());
    assert!(GlobalShortcutService::can_grab_directly("xcb"));
    assert!(!GlobalShortcutService::can_grab_directly("wayland"));
    assert!(GlobalShortcutService::compositor_config_hint("sway").contains("quick-capture"));
}
