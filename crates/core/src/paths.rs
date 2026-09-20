//! Linux XDG data path resolution, isolated from the domain and QML.

use crate::{Error, Result};
use std::{env, ffi::OsStr, fs::DirBuilder, os::unix::fs::DirBuilderExt, path::PathBuf};

pub fn data_directory(xdg_data_home: Option<&OsStr>, home: Option<&OsStr>) -> Result<PathBuf> {
    let absolute = |value: &OsStr| {
        let path = PathBuf::from(value);
        path.is_absolute().then_some(path)
    };
    let base = xdg_data_home.and_then(absolute).or_else(|| {
        home.and_then(absolute)
            .map(|path| path.join(".local/share"))
    });
    Ok(base.ok_or(Error::MissingDataDirectory)?.join("betternotes"))
}

/// Newly created directories are private. Existing directory permissions are preserved.
pub fn database_path() -> Result<PathBuf> {
    let directory = data_directory(
        env::var_os("XDG_DATA_HOME").as_deref(),
        env::var_os("HOME").as_deref(),
    )?;
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&directory)?;
    Ok(directory.join("notes.sqlite3"))
}

pub fn config_directory(xdg_config_home: Option<&OsStr>, home: Option<&OsStr>) -> Result<PathBuf> {
    let absolute = |value: &OsStr| {
        let path = PathBuf::from(value);
        path.is_absolute().then_some(path)
    };
    let base = xdg_config_home
        .and_then(absolute)
        .or_else(|| home.and_then(absolute).map(|path| path.join(".config")));
    base.ok_or(Error::MissingDataDirectory)
}

pub fn autostart_directory(
    xdg_config_home: Option<&OsStr>,
    home: Option<&OsStr>,
) -> Result<PathBuf> {
    Ok(config_directory(xdg_config_home, home)?.join("autostart"))
}

pub fn autostart_file_path() -> Result<PathBuf> {
    let dir = autostart_directory(
        env::var_os("XDG_CONFIG_HOME").as_deref(),
        env::var_os("HOME").as_deref(),
    )?;
    Ok(dir.join("betternotes.desktop"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absolute_xdg_takes_precedence_and_does_not_require_home() {
        assert_eq!(
            data_directory(Some(OsStr::new("/data")), None).unwrap(),
            PathBuf::from("/data/betternotes")
        );
        assert_eq!(
            config_directory(Some(OsStr::new("/config")), None).unwrap(),
            PathBuf::from("/config")
        );
        assert_eq!(
            autostart_directory(Some(OsStr::new("/config")), None).unwrap(),
            PathBuf::from("/config/autostart")
        );
    }

    #[test]
    fn unset_empty_and_relative_xdg_use_home_fallback() {
        for value in [None, Some(OsStr::new("")), Some(OsStr::new("relative"))] {
            assert_eq!(
                data_directory(value, Some(OsStr::new("/home/test"))).unwrap(),
                PathBuf::from("/home/test/.local/share/betternotes")
            );
            assert_eq!(
                config_directory(value, Some(OsStr::new("/home/test"))).unwrap(),
                PathBuf::from("/home/test/.config")
            );
            assert_eq!(
                autostart_directory(value, Some(OsStr::new("/home/test"))).unwrap(),
                PathBuf::from("/home/test/.config/autostart")
            );
        }
        assert!(data_directory(None, None).is_err());
        assert!(data_directory(None, Some(OsStr::new("relative"))).is_err());
        assert!(config_directory(None, None).is_err());
        assert!(autostart_directory(None, None).is_err());
    }
}
