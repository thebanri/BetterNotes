//! Crash-safe atomic backup and restore operations for BetterNotes.

use crate::{Error, Result};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Serialize, Deserialize)]
pub struct BackupManifest {
    pub version: u32,
    pub application: String,
    pub created_at: i64,
    pub note_count: usize,
}

pub fn create_backup(
    connection: &Connection,
    data_dir: &Path,
    target_parent_dir: &Path,
) -> Result<PathBuf> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| Error::Clock)?
        .as_secs();

    let backup_dirname = format!("betternotes-backup-{}", now);
    let backup_dir = target_parent_dir.join(backup_dirname);
    fs::create_dir_all(&backup_dir)?;

    let target_db = backup_dir.join("notes.sqlite3");
    let target_db_str = target_db.to_str().ok_or_else(|| {
        Error::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "Invalid backup path",
        ))
    })?;

    // SQLite's VACUUM INTO creates a crash-consistent, compacted atomic snapshot
    connection.execute(&format!("VACUUM INTO '{}'", target_db_str), [])?;

    // Copy attachments directory if present
    let src_attachments = data_dir.join("attachments");
    let dest_attachments = backup_dir.join("attachments");
    if src_attachments.exists() {
        fs::create_dir_all(&dest_attachments)?;
        for entry in fs::read_dir(&src_attachments)? {
            let entry = entry?;
            let dest_file = dest_attachments.join(entry.file_name());
            fs::copy(entry.path(), dest_file)?;
        }
    }

    let note_count: i64 =
        connection.query_row("SELECT count(*) FROM notes", [], |row| row.get(0))?;

    let manifest = BackupManifest {
        version: 1,
        application: format!(
            "{} v{}",
            crate::APPLICATION_NAME,
            crate::APPLICATION_VERSION
        ),
        created_at: now as i64,
        note_count: note_count as usize,
    };

    let manifest_json = serde_json::to_string_pretty(&manifest)
        .map_err(|e| Error::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, e)))?;
    fs::write(backup_dir.join("manifest.json"), manifest_json)?;

    Ok(backup_dir)
}

pub fn restore_backup(backup_dir: &Path, data_dir: &Path) -> Result<()> {
    let backup_db = backup_dir.join("notes.sqlite3");
    if !backup_db.is_file() {
        return Err(Error::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "Backup database notes.sqlite3 not found in backup directory",
        )));
    }

    // Verify backup database integrity before touching current user data
    {
        let check_conn = Connection::open(&backup_db)?;
        let integrity: String = check_conn.query_row("PRAGMA quick_check", [], |row| row.get(0))?;
        if integrity != "ok" {
            return Err(Error::Io(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("Backup database integrity check failed: {}", integrity),
            )));
        }
    }

    // Safety: Create pre-restore snapshot of existing data directory so user data is never lost
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| Error::Clock)?
        .as_secs();

    if data_dir.exists() {
        let parent = data_dir.parent().unwrap_or(data_dir);
        let pre_restore_dir = parent.join(format!("betternotes.pre-restore.{}", now));
        // Copy current db and attachments to pre_restore_dir
        fs::create_dir_all(&pre_restore_dir)?;
        let cur_db = data_dir.join("notes.sqlite3");
        if cur_db.exists() {
            let _ = fs::copy(&cur_db, pre_restore_dir.join("notes.sqlite3"));
        }
        let cur_att = data_dir.join("attachments");
        if cur_att.exists() {
            let pre_att = pre_restore_dir.join("attachments");
            let _ = fs::create_dir_all(&pre_att);
            if let Ok(entries) = fs::read_dir(&cur_att) {
                for e in entries.flatten() {
                    let _ = fs::copy(e.path(), pre_att.join(e.file_name()));
                }
            }
        }
    }

    // Restore database
    fs::create_dir_all(data_dir)?;
    let dest_db = data_dir.join("notes.sqlite3");
    // Remove WAL and SHM sidecars if present to prevent mixing with old state
    let _ = fs::remove_file(data_dir.join("notes.sqlite3-wal"));
    let _ = fs::remove_file(data_dir.join("notes.sqlite3-shm"));

    fs::copy(&backup_db, &dest_db)?;

    // Restore attachments
    let backup_att = backup_dir.join("attachments");
    if backup_att.exists() {
        let dest_att = data_dir.join("attachments");
        fs::create_dir_all(&dest_att)?;
        for entry in fs::read_dir(&backup_att)? {
            let entry = entry?;
            fs::copy(entry.path(), dest_att.join(entry.file_name()))?;
        }
    }

    Ok(())
}
