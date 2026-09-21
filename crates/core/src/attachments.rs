//! Safe attachment management (files stored in attachments directory, metadata in SQLite).

use crate::{Error, Result};
use rusqlite::{params, Connection, OptionalExtension};
use std::{
    fs,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Attachment {
    pub id: String,
    pub note_id: i64,
    pub filename: String,
    pub mime_type: String,
    pub byte_size: i64,
    pub stored_rel_path: String,
    pub created_at: i64,
}

pub fn attachments_dir(data_dir: &Path) -> Result<PathBuf> {
    let dir = data_dir.join("attachments");
    fs::create_dir_all(&dir)?;
    Ok(dir)
}

pub fn sanitize_filename(filename: &str) -> String {
    let basename = Path::new(filename)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("attachment.bin");

    let sanitized: String = basename
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '.' || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();

    if sanitized.is_empty() || sanitized.starts_with('.') {
        format!("attachment_{}", sanitized)
    } else {
        sanitized
    }
}

pub fn guess_mime_type(filename: &str) -> &'static str {
    let lower = filename.to_lowercase();
    if lower.ends_with(".png") {
        "image/png"
    } else if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        "image/jpeg"
    } else if lower.ends_with(".gif") {
        "image/gif"
    } else if lower.ends_with(".webp") {
        "image/webp"
    } else if lower.ends_with(".bmp") {
        "image/bmp"
    } else if lower.ends_with(".svg") {
        "image/svg+xml"
    } else if lower.ends_with(".txt") {
        "text/plain"
    } else if lower.ends_with(".md") {
        "text/markdown"
    } else if lower.ends_with(".pdf") {
        "application/pdf"
    } else {
        "application/octet-stream"
    }
}

pub fn add_attachment(
    data_dir: &Path,
    connection: &Connection,
    note_id: i64,
    source_path: &Path,
) -> Result<Attachment> {
    if !source_path.is_file() {
        return Err(Error::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "Attachment source file not found",
        )));
    }

    let raw_name = source_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("attachment.bin");
    let safe_name = sanitize_filename(raw_name);
    let mime = guess_mime_type(&safe_name);

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| Error::Clock)?
        .as_millis();
    let id = format!("{:x}_{:x}", now, rand_simple());
    let rel_path = format!("{}_{}", id, safe_name);

    let dest_dir = attachments_dir(data_dir)?;
    let dest_file = dest_dir.join(&rel_path);

    fs::copy(source_path, &dest_file)?;
    // fs::copy keeps the source's mode. An attachment is data: never
    // executable, whatever it was before.
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&dest_file, fs::Permissions::from_mode(0o600))?;
    }
    let meta = fs::metadata(&dest_file)?;
    let byte_size = meta.len() as i64;
    let created_at = (now / 1000) as i64;

    connection.execute(
        "INSERT INTO attachments (id, note_id, filename, mime_type, byte_size, stored_rel_path, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![id, note_id, safe_name, mime, byte_size, rel_path, created_at],
    )?;

    Ok(Attachment {
        id,
        note_id,
        filename: safe_name,
        mime_type: mime.to_string(),
        byte_size,
        stored_rel_path: rel_path,
        created_at,
    })
}

pub fn list_attachments(connection: &Connection, note_id: i64) -> Result<Vec<Attachment>> {
    let mut stmt = connection.prepare(
        "SELECT id, note_id, filename, mime_type, byte_size, stored_rel_path, created_at
         FROM attachments WHERE note_id = ?1 ORDER BY created_at ASC",
    )?;
    let rows = stmt.query_map([note_id], |row| {
        Ok(Attachment {
            id: row.get(0)?,
            note_id: row.get(1)?,
            filename: row.get(2)?,
            mime_type: row.get(3)?,
            byte_size: row.get(4)?,
            stored_rel_path: row.get(5)?,
            created_at: row.get(6)?,
        })
    })?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
}

pub fn delete_attachment(
    data_dir: &Path,
    connection: &Connection,
    attachment_id: &str,
) -> Result<()> {
    let rel_path: Option<String> = connection
        .query_row(
            "SELECT stored_rel_path FROM attachments WHERE id = ?1",
            [attachment_id],
            |row| row.get(0),
        )
        .optional()?;

    if let Some(path) = rel_path {
        let full_path = data_dir.join("attachments").join(path);
        let _ = fs::remove_file(full_path);
    }

    connection.execute("DELETE FROM attachments WHERE id = ?1", [attachment_id])?;
    Ok(())
}

/// Types that run code when "opened": desktop launchers, scripts, programs
/// and installers. Opening an attachment hands it to the desktop's default
/// app, so these are only ever saved, never opened.
const RUNNABLE_EXTENSIONS: &[&str] = &[
    "desktop",
    "sh",
    "bash",
    "zsh",
    "fish",
    "csh",
    "ksh",
    "run",
    "bin",
    "appimage",
    "flatpakref",
    "exe",
    "msi",
    "bat",
    "cmd",
    "com",
    "scr",
    "ps1",
    "vbs",
    "jar",
    "py",
    "pyw",
    "pl",
    "rb",
    "php",
    "deb",
    "rpm",
    "pkg",
    "apk",
    "snap",
    "x86_64",
    "elf",
    "so",
    "out",
];

/// Whether an attachment may be opened with the desktop's default app.
pub fn can_open(filename: &str) -> bool {
    let name = filename.to_lowercase();
    match name.rsplit_once('.') {
        Some((_, extension)) => !RUNNABLE_EXTENSIONS.contains(&extension),
        // No extension: the desktop decides by content, which may be a program.
        None => false,
    }
}

/// Where an attachment's file is stored.
pub fn stored_path(data_dir: &Path, attachment: &Attachment) -> PathBuf {
    data_dir
        .join("attachments")
        .join(&attachment.stored_rel_path)
}

/// The name an attachment had when it was added: its stored file name
/// without the `<time>_<random>_` prefix that keeps stored names unique.
pub fn original_filename(stored_name: &str) -> &str {
    let mut parts = stored_name.splitn(3, '_');
    match (parts.next(), parts.next(), parts.next()) {
        (Some(time), Some(random), Some(name))
            if !name.is_empty()
                && [time, random].iter().all(|part| {
                    !part.is_empty() && part.chars().all(|c| c.is_ascii_hexdigit())
                }) =>
        {
            name
        }
        _ => stored_name,
    }
}

/// Saves a copy of an attachment where the user chose. The copy is written
/// beside the target and renamed over it, so an interrupted save never leaves
/// a truncated file, and the attachment itself is never modified.
pub fn save_copy(source: &Path, target: &Path) -> Result<()> {
    if !source.is_file() {
        return Err(Error::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "The image file no longer exists",
        )));
    }
    if target.is_dir() {
        return Err(Error::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "Choose a file name, not a folder",
        )));
    }
    if fs::canonicalize(source).ok() == fs::canonicalize(target).ok() {
        return Ok(());
    }
    let mut name = target.file_name().unwrap_or_default().to_os_string();
    name.push(".betternotes-partial");
    let partial = target.with_file_name(name);
    let result = fs::copy(source, &partial).and_then(|_| fs::rename(&partial, target));
    if result.is_err() {
        let _ = fs::remove_file(&partial);
    }
    Ok(result?)
}

fn rand_simple() -> u32 {
    let p = std::process::id();
    let t = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(42);
    p.wrapping_mul(1103515245).wrapping_add(t)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_and_mime() {
        assert_eq!(sanitize_filename("../../etc/passwd"), "passwd");
        assert_eq!(sanitize_filename("photo.png"), "photo.png");
        assert_eq!(sanitize_filename("a b c.jpg"), "a_b_c.jpg");
        assert_eq!(guess_mime_type("photo.png"), "image/png");
        assert_eq!(guess_mime_type("doc.pdf"), "application/pdf");
        assert_eq!(guess_mime_type("notes.md"), "text/markdown");
    }

    #[test]
    fn runnable_attachments_are_never_opened() {
        for name in [
            "report.pdf",
            "photo.JPG",
            "notes.md",
            "data.tar.gz",
            "clip.mp4",
        ] {
            assert!(can_open(name), "{name}");
        }
        for name in [
            "evil.desktop",
            "install.sh",
            "App.AppImage",
            "setup.EXE",
            "run.py",
            "tool",
            "lib.so",
            "script.fish",
        ] {
            assert!(!can_open(name), "{name}");
        }
    }

    #[test]
    fn attachments_are_copied_without_execute_permission() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        let store = crate::NoteStore::open(&dir.path().join("notes.sqlite3")).unwrap();
        let note = store.create().unwrap();
        let source = dir.path().join("tool.sh");
        fs::write(&source, "#!/bin/sh\n").unwrap();
        fs::set_permissions(&source, fs::Permissions::from_mode(0o755)).unwrap();
        let attachment =
            add_attachment(dir.path(), store.raw_connection(), note.id, &source).unwrap();
        let mode = fs::metadata(stored_path(dir.path(), &attachment))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }

    #[test]
    fn original_filename_drops_only_the_storage_prefix() {
        assert_eq!(original_filename("1a0c41f74ca_ef7994b2_cat.gif"), "cat.gif");
        assert_eq!(
            original_filename("1a0c_ef79_my_holiday.png"),
            "my_holiday.png"
        );
        assert_eq!(original_filename("holiday_photo.png"), "holiday_photo.png");
        assert_eq!(original_filename("plain.png"), "plain.png");
    }

    #[test]
    fn save_copy_writes_the_image_and_keeps_the_attachment() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("1a_2b_cat.gif");
        fs::write(&source, b"GIF89a").unwrap();
        let target = dir.path().join("saved.gif");
        fs::write(&target, b"old").unwrap();

        save_copy(&source, &target).unwrap();
        assert_eq!(fs::read(&target).unwrap(), b"GIF89a");
        assert_eq!(fs::read(&source).unwrap(), b"GIF89a");
        assert!(!dir.path().join("saved.gif.betternotes-partial").exists());

        save_copy(&source, &source).unwrap();
        assert_eq!(fs::read(&source).unwrap(), b"GIF89a");
        assert!(save_copy(&source, dir.path()).is_err());
        assert!(save_copy(&dir.path().join("missing.png"), &target).is_err());
    }
}
