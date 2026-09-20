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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absolute_xdg_takes_precedence_and_does_not_require_home() {
        assert_eq!(
            data_directory(Some(OsStr::new("/data")), None).unwrap(),
            PathBuf::from("/data/betternotes")
        );
    }

    #[test]
    fn unset_empty_and_relative_xdg_use_home_fallback() {
        for value in [None, Some(OsStr::new("")), Some(OsStr::new("relative"))] {
            assert_eq!(
                data_directory(value, Some(OsStr::new("/home/test"))).unwrap(),
                PathBuf::from("/home/test/.local/share/betternotes")
            );
        }
        assert!(data_directory(None, None).is_err());
        assert!(data_directory(None, Some(OsStr::new("relative"))).is_err());
    }
}
