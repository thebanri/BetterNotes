//! Freedesktop desktop notifications interface.

use crate::{Result, APPLICATION_ID};
use std::{
    ffi::{OsStr, OsString},
    fs,
    path::{Path, PathBuf},
    process::Command,
};

/// Replaces `notify-send`; the test suites point it at `true` so running the
/// tests does not put notifications on the developer's desktop.
const PROGRAM_OVERRIDE: &str = "BETTERNOTES_NOTIFY_SEND";

pub struct NotificationService;

impl NotificationService {
    /// Dispatches a notification using standard Freedesktop mechanisms (`notify-send`).
    /// Fails gracefully if no notification daemon is active or notify-send is absent.
    pub fn notify(title: &str, body: &str) -> Result<bool> {
        let program = std::env::var_os(PROGRAM_OVERRIDE)
            .filter(|program| !program.is_empty())
            .unwrap_or_else(|| "notify-send".into());
        let icon = notification_icon(
            &icon_search_dirs(
                std::env::var_os("XDG_DATA_HOME").as_deref(),
                std::env::var_os("XDG_DATA_DIRS").as_deref(),
                std::env::var_os("HOME").as_deref(),
            ),
            cache_directory().as_deref(),
            std::env::var_os("FLATPAK_ID").is_some(),
        );
        match command(&program, &icon, title, body).status() {
            Ok(s) => Ok(s.success()),
            Err(e) => {
                eprintln!("BetterNotes: notification service notice: {e}");
                Ok(false)
            }
        }
    }
}

impl NotificationService {
    /// Shows a notification with buttons and waits until it is closed.
    /// Returns the name of the button pressed, if any. Blocks, so callers run
    /// it off the GUI thread. Falls back to a plain notification when the
    /// installed notify-send has no buttons.
    pub fn notify_with_actions(
        title: &str,
        body: &str,
        actions: &[(&str, &str)],
    ) -> Result<Option<String>> {
        let program = std::env::var_os(PROGRAM_OVERRIDE)
            .filter(|program| !program.is_empty())
            .unwrap_or_else(|| "notify-send".into());
        let icon = notification_icon(
            &icon_search_dirs(
                std::env::var_os("XDG_DATA_HOME").as_deref(),
                std::env::var_os("XDG_DATA_DIRS").as_deref(),
                std::env::var_os("HOME").as_deref(),
            ),
            cache_directory().as_deref(),
            std::env::var_os("FLATPAK_ID").is_some(),
        );
        let mut command = command(&program, &icon, title, body);
        // Options must come before "--"; rebuild with the actions in front.
        let mut arguments: Vec<std::ffi::OsString> =
            command.get_args().map(|arg| arg.to_os_string()).collect();
        let separator = arguments.iter().position(|arg| arg == "--").unwrap_or(0);
        for (name, label) in actions.iter().rev() {
            arguments.insert(separator, format!("--action={name}={label}").into());
        }
        command = Command::new(&program);
        command.args(arguments);
        match command.output() {
            Ok(output) if output.status.success() => {
                let chosen = String::from_utf8_lossy(&output.stdout).trim().to_string();
                Ok(actions
                    .iter()
                    .find(|(name, _)| *name == chosen)
                    .map(|(name, _)| name.to_string()))
            }
            Ok(_) => Self::notify(title, body).map(|_| None),
            Err(e) => {
                eprintln!("BetterNotes: notification service notice: {e}");
                Ok(None)
            }
        }
    }
}

fn command(program: &OsStr, icon: &str, title: &str, body: &str) -> Command {
    let mut command = Command::new(program);
    command
        .arg("--app-name=BetterNotes")
        .arg(format!("--icon={icon}"))
        // Lets the notification server show the app's own name and icon.
        .arg(format!("--hint=string:desktop-entry:{APPLICATION_ID}"))
        // Note titles are user text: one starting with "-" is not an option.
        .arg("--")
        .arg(title)
        .arg(body);
    command
}

/// The icon to show: the app's theme icon when it is installed where the
/// notification server can look it up, otherwise the bundled icon written to
/// the cache, since an AppImage or a build tree has no theme icon.
fn notification_icon(search_dirs: &[PathBuf], cache: Option<&Path>, flatpak: bool) -> String {
    // A Flatpak exports its icon to the host; a cache path inside the sandbox
    // would mean nothing to the host's notification server.
    let installed = search_dirs.iter().any(|dir| {
        let theme = dir.join("icons/hicolor");
        theme
            .join(format!("scalable/apps/{APPLICATION_ID}.svg"))
            .is_file()
            || theme
                .join(format!("128x128/apps/{APPLICATION_ID}.png"))
                .is_file()
    });
    if flatpak || installed {
        return APPLICATION_ID.to_string();
    }
    cache
        .and_then(|cache| bundled_icon(cache).ok())
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_else(|| APPLICATION_ID.to_string())
}

fn bundled_icon(cache: &Path) -> std::io::Result<PathBuf> {
    let path = cache.join(format!("{APPLICATION_ID}.png"));
    if fs::read(&path).ok().as_deref() != Some(crate::install::NOTIFICATION_ICON) {
        fs::create_dir_all(cache)?;
        let partial = cache.join(format!("{APPLICATION_ID}.png.partial"));
        fs::write(&partial, crate::install::NOTIFICATION_ICON)?;
        fs::rename(&partial, &path)?;
    }
    Ok(path)
}

/// `$XDG_DATA_HOME` and `$XDG_DATA_DIRS`, with the specification's defaults.
fn icon_search_dirs(
    data_home: Option<&OsStr>,
    data_dirs: Option<&OsStr>,
    home: Option<&OsStr>,
) -> Vec<PathBuf> {
    let absolute = |path: PathBuf| path.is_absolute().then_some(path);
    let mut dirs: Vec<PathBuf> = data_home
        .map(PathBuf::from)
        .and_then(absolute)
        .or_else(|| home.map(|home| PathBuf::from(home).join(".local/share")))
        .into_iter()
        .collect();
    let system = data_dirs
        .filter(|dirs| !dirs.is_empty())
        .map(OsString::from)
        .unwrap_or_else(|| "/usr/local/share:/usr/share".into());
    dirs.extend(std::env::split_paths(&system).filter_map(absolute));
    dirs
}

fn cache_directory() -> Option<PathBuf> {
    std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
        .map(|cache| cache.join("betternotes"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_passes_icon_hint_and_user_text_as_arguments() {
        let command = command(
            OsStr::new("notify-send"),
            "/cache/icon.png",
            "-rf title",
            "body",
        );
        let args: Vec<_> = command.get_args().collect();
        assert_eq!(
            args,
            [
                "--app-name=BetterNotes",
                "--icon=/cache/icon.png",
                "--hint=string:desktop-entry:org.betternotes.BetterNotes",
                "--",
                "-rf title",
                "body",
            ]
        );
    }

    #[test]
    fn icon_is_the_theme_name_when_installed_and_a_cached_file_otherwise() {
        let root = tempfile::tempdir().unwrap();
        let data = root.path().join("data");
        let cache = root.path().join("cache");

        let icon = notification_icon(std::slice::from_ref(&data), Some(&cache), false);
        assert_eq!(
            icon,
            cache
                .join("org.betternotes.BetterNotes.png")
                .to_string_lossy()
        );
        assert_eq!(fs::read(&icon).unwrap(), crate::install::NOTIFICATION_ICON);
        // Reuses the file already written.
        assert_eq!(
            notification_icon(std::slice::from_ref(&data), Some(&cache), false),
            icon
        );

        assert_eq!(notification_icon(&[], None, true), APPLICATION_ID);
        let apps = data.join("icons/hicolor/scalable/apps");
        fs::create_dir_all(&apps).unwrap();
        fs::write(apps.join("org.betternotes.BetterNotes.svg"), "<svg/>").unwrap();
        assert_eq!(
            notification_icon(&[data], Some(&cache), false),
            APPLICATION_ID
        );
    }

    #[test]
    fn actions_go_before_the_title_and_the_chosen_one_is_reported() {
        let dir = tempfile::tempdir().unwrap();
        let fake = dir.path().join("notify-send");
        // Prints the arguments it got, then answers "open" as if clicked.
        std::fs::write(
            &fake,
            format!(
                "#!/bin/sh\nprintf '%s\\n' \"$@\" > {}\necho open\n",
                dir.path().join("args").display()
            ),
        )
        .unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&fake, std::fs::Permissions::from_mode(0o755)).unwrap();
        std::env::set_var(PROGRAM_OVERRIDE, &fake);
        let chosen = NotificationService::notify_with_actions(
            "-title",
            "body",
            &[("open", "Open note"), ("snooze", "Snooze")],
        )
        .unwrap();
        std::env::remove_var(PROGRAM_OVERRIDE);
        assert_eq!(chosen.as_deref(), Some("open"));
        let args = std::fs::read_to_string(dir.path().join("args")).unwrap();
        let args: Vec<&str> = args.lines().collect();
        let separator = args.iter().position(|arg| *arg == "--").unwrap();
        assert!(args[..separator].contains(&"--action=open=Open note"));
        assert!(args[..separator].contains(&"--action=snooze=Snooze"));
        assert_eq!(&args[separator + 1..], ["-title", "body"]);
    }

    #[test]
    fn search_dirs_follow_xdg_defaults() {
        assert_eq!(
            icon_search_dirs(None, None, Some(OsStr::new("/home/me"))),
            [
                PathBuf::from("/home/me/.local/share"),
                PathBuf::from("/usr/local/share"),
                PathBuf::from("/usr/share"),
            ]
        );
        assert_eq!(
            icon_search_dirs(
                Some(OsStr::new("/data")),
                Some(OsStr::new("/a:relative")),
                None
            ),
            [PathBuf::from("/data"), PathBuf::from("/a")]
        );
    }
}
