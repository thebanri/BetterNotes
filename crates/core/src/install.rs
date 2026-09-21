//! Per-user desktop installation: puts BetterNotes in the applications menu.
//!
//! A build started from a source tree or a downloaded binary has no desktop
//! entry, so the desktop cannot show it in menus or give its windows the right
//! icon. Installing copies the binary to `~/.local/bin`, writes the desktop
//! entry to `$XDG_DATA_HOME/applications` and the icons to the hicolor theme
//! under `$XDG_DATA_HOME/icons`. Nothing needs root, and uninstalling removes
//! only these files, never notes or settings.

use crate::{autostart, Error, Result, APPLICATION_ID};
use std::{
    ffi::OsStr,
    fs::{self, DirBuilder},
    io::Write,
    os::unix::fs::{DirBuilderExt, PermissionsExt},
    path::{Path, PathBuf},
};

/// Marks a desktop entry written by [`install`], so uninstalling never removes
/// one that a package or the user put there.
const MARKER: &str = "X-BetterNotes-Installed=true";

const SVG_ICON: &[u8] = include_bytes!("../../../assets/icons/org.betternotes.BetterNotes.svg");
const PNG_ICONS: [(u32, &[u8]); 8] = [
    (
        16,
        include_bytes!("../../../assets/icons/hicolor/org.betternotes.BetterNotes-16.png"),
    ),
    (
        22,
        include_bytes!("../../../assets/icons/hicolor/org.betternotes.BetterNotes-22.png"),
    ),
    (
        24,
        include_bytes!("../../../assets/icons/hicolor/org.betternotes.BetterNotes-24.png"),
    ),
    (
        32,
        include_bytes!("../../../assets/icons/hicolor/org.betternotes.BetterNotes-32.png"),
    ),
    (
        48,
        include_bytes!("../../../assets/icons/hicolor/org.betternotes.BetterNotes-48.png"),
    ),
    (
        64,
        include_bytes!("../../../assets/icons/hicolor/org.betternotes.BetterNotes-64.png"),
    ),
    (
        128,
        include_bytes!("../../../assets/icons/hicolor/org.betternotes.BetterNotes-128.png"),
    ),
    (
        256,
        include_bytes!("../../../assets/icons/hicolor/org.betternotes.BetterNotes-256.png"),
    ),
];

/// Where a per-user installation puts its files.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallLayout {
    pub binary: PathBuf,
    pub desktop_entry: PathBuf,
    pub icon_theme: PathBuf,
}

impl InstallLayout {
    pub fn resolve(xdg_data_home: Option<&OsStr>, home: Option<&OsStr>) -> Result<Self> {
        let absolute = |value: &OsStr| {
            let path = PathBuf::from(value);
            path.is_absolute().then_some(path)
        };
        let home = home.and_then(absolute);
        let data_home = xdg_data_home
            .and_then(absolute)
            .or_else(|| home.as_ref().map(|home| home.join(".local/share")))
            .ok_or(Error::MissingDataDirectory)?;
        // The XDG base directory specification names ~/.local/bin for user
        // executables; it has no variable of its own.
        let home = home.ok_or(Error::MissingDataDirectory)?;
        Ok(Self {
            binary: home.join(".local/bin/betternotes"),
            desktop_entry: data_home
                .join("applications")
                .join(format!("{APPLICATION_ID}.desktop")),
            icon_theme: data_home.join("icons/hicolor"),
        })
    }

    pub fn current() -> Result<Self> {
        Self::resolve(
            std::env::var_os("XDG_DATA_HOME").as_deref(),
            std::env::var_os("HOME").as_deref(),
        )
    }

    fn icon_files(&self) -> Vec<PathBuf> {
        let mut files = vec![self
            .icon_theme
            .join(format!("scalable/apps/{APPLICATION_ID}.svg"))];
        files.extend(PNG_ICONS.iter().map(|(size, _)| {
            self.icon_theme
                .join(format!("{size}x{size}/apps/{APPLICATION_ID}.png"))
        }));
        files
    }
}

/// How the running BetterNotes was started, which decides what installing means.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallSource {
    /// A plain binary, e.g. `target/release/betternotes`: copy it.
    Binary(PathBuf),
    /// An AppImage: launch that file where it is, since its binary needs the
    /// libraries bundled next to it.
    AppImage(PathBuf),
    /// Installed by a package manager or Flatpak, which already provides the
    /// desktop entry and icons.
    Managed,
}

impl InstallSource {
    pub fn detect() -> Result<Self> {
        if std::env::var_os("FLATPAK_ID").is_some() {
            return Ok(Self::Managed);
        }
        if let Some(appimage) = std::env::var_os("APPIMAGE").filter(|path| !path.is_empty()) {
            return Ok(Self::AppImage(PathBuf::from(appimage)));
        }
        let exe = std::env::current_exe()?;
        if exe.starts_with("/usr") {
            return Ok(Self::Managed);
        }
        Ok(Self::Binary(exe))
    }
}

/// Whether this user's applications menu has a BetterNotes entry from [`install`].
pub fn is_installed(layout: &InstallLayout) -> bool {
    fs::read_to_string(&layout.desktop_entry).is_ok_and(|entry| entry.contains(MARKER))
}

/// Installs BetterNotes for the current user and returns the command the
/// desktop entry launches.
pub fn install(layout: &InstallLayout, source: &InstallSource) -> Result<String> {
    let exec = match source {
        InstallSource::Managed => {
            return Err(Error::Install(
                "BetterNotes is already installed by your package manager or Flatpak".into(),
            ))
        }
        InstallSource::AppImage(path) => path.clone(),
        InstallSource::Binary(exe) => {
            let same = fs::canonicalize(exe).ok() == fs::canonicalize(&layout.binary).ok();
            if !same {
                copy_executable(exe, &layout.binary)?;
            }
            layout.binary.clone()
        }
    };
    let exec = autostart::desktop_exec_quote(&exec.to_string_lossy());

    for (size, bytes) in PNG_ICONS {
        write_atomically(
            &layout
                .icon_theme
                .join(format!("{size}x{size}/apps/{APPLICATION_ID}.png")),
            bytes,
            0o644,
        )?;
    }
    write_atomically(
        &layout
            .icon_theme
            .join(format!("scalable/apps/{APPLICATION_ID}.svg")),
        SVG_ICON,
        0o644,
    )?;
    // The entry goes last: once it exists, the menu shows an app that works.
    write_atomically(
        &layout.desktop_entry,
        desktop_entry(&exec).as_bytes(),
        0o644,
    )?;
    Ok(exec)
}

/// Points an enabled login entry at the installed command, so logging in
/// starts this installation even when `~/.local/bin` is not on the PATH.
/// `None` restores the default command after uninstalling.
pub fn refresh_autostart(exec: Option<&str>) -> Result<()> {
    if autostart::is_autostart_enabled()? {
        autostart::set_autostart(true, exec)?;
    }
    Ok(())
}

/// Installs the running BetterNotes for this user, as the CLI and the
/// settings page do, and describes the result.
pub fn install_for_current_user() -> Result<String> {
    let layout = InstallLayout::current()?;
    let exec = install(&layout, &InstallSource::detect()?)?;
    refresh_autostart(Some(&exec))?;
    Ok(format!(
        "BetterNotes was added to your applications menu; it launches {exec}"
    ))
}

/// Reverses [`install_for_current_user`].
pub fn uninstall_for_current_user() -> Result<String> {
    uninstall(&InstallLayout::current()?)?;
    refresh_autostart(None)?;
    Ok("BetterNotes was removed from your applications menu. Notes were kept.".into())
}

/// Removes what [`install`] added. Notes, settings and attachments stay.
pub fn uninstall(layout: &InstallLayout) -> Result<()> {
    if !is_installed(layout) {
        return Err(Error::Install(
            "BetterNotes is not installed in this user's applications menu".into(),
        ));
    }
    let entry = fs::read_to_string(&layout.desktop_entry)?;
    // Remove the entry first so the menu never offers a missing binary.
    fs::remove_file(&layout.desktop_entry)?;
    for icon in layout.icon_files() {
        remove_if_present(&icon)?;
    }
    // Only a binary this entry launches is ours to delete.
    let binary = autostart::desktop_exec_quote(&layout.binary.to_string_lossy());
    if entry.lines().any(|line| line == format!("Exec={binary}")) {
        remove_if_present(&layout.binary)?;
    }
    Ok(())
}

fn desktop_entry(exec: &str) -> String {
    format!(
        "[Desktop Entry]
Type=Application
Name=BetterNotes
GenericName=Sticky Notes
Comment=Sticky notes for the Linux desktop
Exec={exec}
Icon={APPLICATION_ID}
Terminal=false
Categories=Utility;
StartupNotify=true
StartupWMClass=betternotes
Keywords=notes;sticky;workspace;markdown;reminders;todo;scratchpad;
Actions=NewNote;QuickCapture;
{MARKER}

[Desktop Action NewNote]
Name=New Note
Exec={exec} new \"\"

[Desktop Action QuickCapture]
Name=Quick Capture
Exec={exec} --quick-capture
"
    )
}

fn create_parent(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        DirBuilder::new()
            .recursive(true)
            .mode(0o755)
            .create(parent)?;
    }
    Ok(())
}

/// Writes through a temporary file in the same directory and renames it over
/// the target, so an interrupted install never leaves a truncated file.
fn write_atomically(path: &Path, bytes: &[u8], mode: u32) -> Result<()> {
    create_parent(path)?;
    let temporary = temporary_path(path);
    let result = (|| {
        let mut file = fs::File::create(&temporary)?;
        file.write_all(bytes)?;
        file.set_permissions(fs::Permissions::from_mode(mode))?;
        file.sync_all()?;
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    Ok(result?)
}

/// Copies the running executable. Renaming over the target replaces a binary
/// that is currently running instead of failing with "text file busy".
fn copy_executable(source: &Path, target: &Path) -> Result<()> {
    create_parent(target)?;
    let temporary = temporary_path(target);
    let result = (|| {
        fs::copy(source, &temporary)?;
        fs::set_permissions(&temporary, fs::Permissions::from_mode(0o755))?;
        fs::rename(&temporary, target)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    Ok(result?)
}

fn temporary_path(path: &Path) -> PathBuf {
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(".betternotes-install");
    path.with_file_name(name)
}

fn remove_if_present(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(error.into()),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn layout(root: &Path) -> InstallLayout {
        InstallLayout::resolve(
            Some(root.join("data").as_os_str()),
            Some(root.join("home").as_os_str()),
        )
        .unwrap()
    }

    #[test]
    fn layout_follows_xdg_data_home_and_falls_back_to_home() {
        let layout =
            InstallLayout::resolve(Some(OsStr::new("/data")), Some(OsStr::new("/home/test")))
                .unwrap();
        assert_eq!(
            layout.binary,
            PathBuf::from("/home/test/.local/bin/betternotes")
        );
        assert_eq!(
            layout.desktop_entry,
            PathBuf::from("/data/applications/org.betternotes.BetterNotes.desktop")
        );
        assert_eq!(layout.icon_theme, PathBuf::from("/data/icons/hicolor"));

        let fallback =
            InstallLayout::resolve(Some(OsStr::new("relative")), Some(OsStr::new("/home/test")))
                .unwrap();
        assert_eq!(
            fallback.desktop_entry,
            PathBuf::from(
                "/home/test/.local/share/applications/org.betternotes.BetterNotes.desktop"
            )
        );
        assert!(InstallLayout::resolve(Some(OsStr::new("/data")), None).is_err());
    }

    #[test]
    fn install_and_uninstall_a_binary() {
        let root = tempfile::tempdir().unwrap();
        let layout = layout(root.path());
        let exe = root.path().join("build/betternotes");
        fs::create_dir_all(exe.parent().unwrap()).unwrap();
        fs::write(&exe, b"binary").unwrap();

        assert!(!is_installed(&layout));
        let exec = install(&layout, &InstallSource::Binary(exe.clone())).unwrap();
        assert!(is_installed(&layout));
        assert_eq!(fs::read(&layout.binary).unwrap(), b"binary");
        let mode = fs::metadata(&layout.binary).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o755);
        let entry = fs::read_to_string(&layout.desktop_entry).unwrap();
        assert!(entry.contains(&format!("Exec={exec}\n")));
        assert!(entry.contains("Icon=org.betternotes.BetterNotes\n"));
        for icon in layout.icon_files() {
            assert!(icon.is_file(), "missing {}", icon.display());
        }

        // Installing again from the installed copy keeps it in place.
        install(&layout, &InstallSource::Binary(layout.binary.clone())).unwrap();
        assert_eq!(fs::read(&layout.binary).unwrap(), b"binary");

        uninstall(&layout).unwrap();
        assert!(!is_installed(&layout));
        assert!(!layout.binary.exists());
        assert!(!layout.desktop_entry.exists());
        assert!(layout.icon_files().iter().all(|icon| !icon.exists()));
        assert!(exe.exists(), "the source binary must survive");
        assert!(uninstall(&layout).is_err());
    }

    #[test]
    fn appimage_installs_without_copying_and_managed_builds_refuse() {
        let root = tempfile::tempdir().unwrap();
        let layout = layout(root.path());
        let appimage = PathBuf::from("/home/me/My Apps/BetterNotes.AppImage");
        install(&layout, &InstallSource::AppImage(appimage)).unwrap();
        let entry = fs::read_to_string(&layout.desktop_entry).unwrap();
        assert!(entry.contains("Exec=\"/home/me/My Apps/BetterNotes.AppImage\"\n"));
        assert!(!layout.binary.exists());
        uninstall(&layout).unwrap();

        assert!(install(&layout, &InstallSource::Managed).is_err());
        assert!(!layout.desktop_entry.exists());
    }

    #[test]
    fn uninstall_leaves_entries_it_did_not_write() {
        let root = tempfile::tempdir().unwrap();
        let layout = layout(root.path());
        fs::create_dir_all(layout.desktop_entry.parent().unwrap()).unwrap();
        fs::write(&layout.desktop_entry, "[Desktop Entry]\nExec=betternotes\n").unwrap();
        assert!(!is_installed(&layout));
        assert!(uninstall(&layout).is_err());
        assert!(layout.desktop_entry.exists());
    }
}
