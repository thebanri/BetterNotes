//! XDG autostart management for Linux desktop login.

use crate::{paths, Result};
use std::fs::{self, DirBuilder, File};
use std::io::Write;
use std::os::unix::fs::DirBuilderExt;
use std::path::Path;

const DESKTOP_TEMPLATE: &str = r#"[Desktop Entry]
Type=Application
Name=BetterNotes
GenericName=Sticky Notes
Comment=Lightweight desktop sticky notes and workspace
Exec={EXEC} --background
Icon=betternotes
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
"#;

pub fn is_autostart_enabled() -> Result<bool> {
    let path = paths::autostart_file_path()?;
    Ok(is_autostart_enabled_at(&path))
}

pub fn set_autostart(enabled: bool, exec_path: Option<&str>) -> Result<()> {
    let path = paths::autostart_file_path()?;
    let exec = exec_path.unwrap_or("betternotes");
    set_autostart_at(&path, enabled, exec)
}

pub fn is_autostart_enabled_at(path: &Path) -> bool {
    if !path.exists() {
        return false;
    }
    match fs::read_to_string(path) {
        Ok(content) => {
            !content.contains("Hidden=true") && !content.contains("X-GNOME-Autostart-enabled=false")
        }
        Err(_) => false,
    }
}

pub fn set_autostart_at(path: &Path, enabled: bool, exec: &str) -> Result<()> {
    if enabled {
        if let Some(parent) = path.parent() {
            DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(parent)?;
        }
        let content = DESKTOP_TEMPLATE.replace("{EXEC}", exec);
        let mut file = File::create(path)?;
        file.write_all(content.as_bytes())?;
        file.flush()?;
    } else if path.exists() {
        fs::remove_file(path)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn autostart_file_toggle_and_detection() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("autostart/betternotes.desktop");

        assert!(!is_autostart_enabled_at(&path));

        set_autostart_at(&path, true, "/usr/bin/betternotes").unwrap();
        assert!(is_autostart_enabled_at(&path));

        let content = fs::read_to_string(&path).unwrap();
        assert!(content.contains("Exec=/usr/bin/betternotes --background"));
        assert!(content.contains("X-GNOME-Autostart-enabled=true"));

        set_autostart_at(&path, false, "/usr/bin/betternotes").unwrap();
        assert!(!is_autostart_enabled_at(&path));
        assert!(!path.exists());
    }
}
