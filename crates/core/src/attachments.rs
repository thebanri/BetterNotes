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
}
