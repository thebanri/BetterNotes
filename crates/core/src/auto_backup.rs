//! Automatic backups: a daily or weekly copy of the notes and attachments,
//! keeping the newest few. Settings live in the notes database.

use crate::{backup, Error, NoteStore, Result};
use std::{
    fs,
    path::{Path, PathBuf},
};

const ENABLED_KEY: &str = "auto_backup_enabled";
const INTERVAL_KEY: &str = "auto_backup_interval";
const KEEP_KEY: &str = "auto_backup_keep";
const FOLDER_KEY: &str = "auto_backup_folder";
const LAST_KEY: &str = "auto_backup_last";
const DAY_SECONDS: i64 = 24 * 60 * 60;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AutoBackupSettings {
    pub enabled: bool,
    /// "daily" or "weekly".
    pub interval: String,
    /// How many automatic backups to keep, 1 to 100.
    pub keep: u32,
    /// Where backups go; empty means the default folder.
    pub folder: String,
    /// When the last automatic backup was made (Unix seconds), 0 for never.
    pub last: i64,
}

impl AutoBackupSettings {
    pub fn load(store: &NoteStore) -> Result<Self> {
        let get = |key| store.get_setting(key).map(Option::unwrap_or_default);
        Ok(Self {
            enabled: get(ENABLED_KEY)? != "false",
            interval: match get(INTERVAL_KEY)?.as_str() {
                "weekly" => "weekly".into(),
                _ => "daily".into(),
            },
            keep: get(KEEP_KEY)?.parse().unwrap_or(7).clamp(1, 100),
            folder: get(FOLDER_KEY)?,
            last: get(LAST_KEY)?.parse().unwrap_or(0),
        })
    }

    pub fn save(&self, store: &NoteStore) -> Result<()> {
        if self.folder.trim().len() > 4096
            || (!self.folder.is_empty() && !Path::new(&self.folder).is_absolute())
        {
            return Err(Error::Io(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "Choose a backup folder by its full path",
            )));
        }
        store.set_setting(ENABLED_KEY, if self.enabled { "true" } else { "false" })?;
        store.set_setting(
            INTERVAL_KEY,
            if self.interval == "weekly" {
                "weekly"
            } else {
                "daily"
            },
        )?;
        store.set_setting(KEEP_KEY, &self.keep.clamp(1, 100).to_string())?;
        store.set_setting(FOLDER_KEY, self.folder.trim())
    }

    fn interval_seconds(&self) -> i64 {
        if self.interval == "weekly" {
            7 * DAY_SECONDS
        } else {
            DAY_SECONDS
        }
    }

    /// The folder backups are written to.
    pub fn target(&self, data_dir: &Path) -> PathBuf {
        if self.folder.is_empty() {
            data_dir.join("backups")
        } else {
            PathBuf::from(&self.folder)
        }
    }
}

/// Makes an automatic backup when one is due, then removes the oldest beyond
/// the number to keep. Returns the new backup's folder, if one was made.
pub fn run_if_due(store: &NoteStore, data_dir: &Path, now: i64) -> Result<Option<PathBuf>> {
    let settings = AutoBackupSettings::load(store)?;
    if !settings.enabled || now - settings.last < settings.interval_seconds() {
        return Ok(None);
    }
    backup_now(store, data_dir).map(Some)
}

/// Makes a backup in the configured folder now and prunes old ones.
pub fn backup_now(store: &NoteStore, data_dir: &Path) -> Result<PathBuf> {
    let settings = AutoBackupSettings::load(store)?;
    let target = settings.target(data_dir);
    fs::create_dir_all(&target)?;
    let made = backup::create_backup(store.raw_connection(), data_dir, &target)?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| Error::Clock)?
        .as_secs() as i64;
    store.set_setting(LAST_KEY, &now.to_string())?;
    prune(&target, settings.keep as usize)?;
    Ok(made)
}

/// Deletes all but the newest `keep` backups in a folder. Only folders this
/// app named ("betternotes-backup-<seconds>") are ever touched.
pub fn prune(folder: &Path, keep: usize) -> Result<usize> {
    let mut backups: Vec<(u64, PathBuf)> = fs::read_dir(folder)?
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().into_string().ok()?;
            let stamp = name.strip_prefix("betternotes-backup-")?.parse().ok()?;
            entry
                .file_type()
                .ok()?
                .is_dir()
                .then(|| (stamp, entry.path()))
        })
        .collect();
    backups.sort_by_key(|backup| std::cmp::Reverse(backup.0));
    let mut removed = 0;
    for (_, path) in backups.into_iter().skip(keep.max(1)) {
        fs::remove_dir_all(path)?;
        removed += 1;
    }
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_default_and_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let store = NoteStore::open(&dir.path().join("notes.sqlite3")).unwrap();
        let defaults = AutoBackupSettings::load(&store).unwrap();
        assert!(defaults.enabled);
        assert_eq!(defaults.interval, "daily");
        assert_eq!(defaults.keep, 7);
        assert_eq!(defaults.target(dir.path()), dir.path().join("backups"));

        let custom = AutoBackupSettings {
            enabled: false,
            interval: "weekly".into(),
            keep: 500,
            folder: "/backups/notes".into(),
            last: 0,
        };
        custom.save(&store).unwrap();
        let loaded = AutoBackupSettings::load(&store).unwrap();
        assert!(!loaded.enabled);
        assert_eq!(loaded.interval, "weekly");
        assert_eq!(loaded.keep, 100);
        assert_eq!(loaded.target(dir.path()), PathBuf::from("/backups/notes"));
        let relative = AutoBackupSettings {
            folder: "relative".into(),
            ..loaded
        };
        assert!(relative.save(&store).is_err());
    }

    #[test]
    fn backs_up_when_due_and_keeps_the_newest() {
        let dir = tempfile::tempdir().unwrap();
        let store = NoteStore::open(&dir.path().join("notes.sqlite3")).unwrap();
        store.create().unwrap();
        let backups = dir.path().join("backups");
        fs::create_dir_all(&backups).unwrap();
        // Older automatic backups and an unrelated folder the user keeps there.
        for stamp in [100, 200, 300] {
            fs::create_dir_all(backups.join(format!("betternotes-backup-{stamp}"))).unwrap();
        }
        fs::create_dir_all(backups.join("my things")).unwrap();
        AutoBackupSettings {
            keep: 2,
            ..AutoBackupSettings::load(&store).unwrap()
        }
        .save(&store)
        .unwrap();

        let now = 10 * DAY_SECONDS;
        let made = run_if_due(&store, dir.path(), now).unwrap().expect("due");
        assert!(made.join("notes.sqlite3").is_file());
        assert!(made.join("manifest.json").is_file());
        let mut left: Vec<String> = fs::read_dir(&backups)
            .unwrap()
            .flatten()
            .map(|entry| entry.file_name().into_string().unwrap())
            .collect();
        left.sort();
        assert_eq!(left.len(), 3, "{left:?}");
        assert!(left.contains(&"my things".to_string()));
        assert!(left.contains(&"betternotes-backup-300".to_string()));

        // Not due again until the interval has passed.
        let last = AutoBackupSettings::load(&store).unwrap().last;
        assert!(run_if_due(&store, dir.path(), last + 60).unwrap().is_none());
    }
}
