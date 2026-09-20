//! Safe import and export of notes in JSON, Markdown, and Plain Text formats.

use crate::{Error, NoteStore, Result};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExportNote {
    pub title: String,
    pub content: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub priority: i32,
    #[serde(default)]
    pub is_pinned: bool,
    #[serde(default)]
    pub is_archived: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ExportArchive {
    pub version: u32,
    pub generator: String,
    pub exported_at: i64,
    pub notes: Vec<ExportNote>,
}

pub fn export_notes_json(notes: &[ExportNote], output_path: &Path) -> Result<()> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| Error::Clock)?
        .as_secs() as i64;

    let archive = ExportArchive {
        version: 1,
        generator: format!(
            "{} v{}",
            crate::APPLICATION_NAME,
            crate::APPLICATION_VERSION
        ),
        exported_at: now,
        notes: notes.to_vec(),
    };

    let json = serde_json::to_string_pretty(&archive)
        .map_err(|e| Error::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, e)))?;

    // Atomic write to avoid partial/corrupted export files
    let tmp_path = output_path.with_extension("tmp_export");
    fs::write(&tmp_path, json)?;
    fs::rename(&tmp_path, output_path)?;
    Ok(())
}

pub fn export_notes_markdown_dir(notes: &[ExportNote], output_dir: &Path) -> Result<()> {
    fs::create_dir_all(output_dir)?;

    for (index, note) in notes.iter().enumerate() {
        let safe_title: String = note
            .title
            .chars()
            .map(|c| {
                if c.is_alphanumeric() || c == ' ' || c == '_' || c == '-' {
                    c
                } else {
                    '_'
                }
            })
            .collect();
        let safe_title = safe_title.trim();
        let filename = if safe_title.is_empty() {
            format!("note_{}.md", index + 1)
        } else {
            format!("{}_{}.md", index + 1, safe_title)
        };

        let file_path = output_dir.join(filename);
        let tags_line = if note.tags.is_empty() {
            String::new()
        } else {
            format!("tags: [{}]\n", note.tags.join(", "))
        };

        let content = format!(
            "---\ntitle: {}\npriority: {}\npinned: {}\narchived: {}\n{}---\n\n{}",
            note.title, note.priority, note.is_pinned, note.is_archived, tags_line, note.content
        );

        fs::write(file_path, content)?;
    }
    Ok(())
}

pub fn import_notes_json(store: &NoteStore, input_path: &Path) -> Result<usize> {
    let content = fs::read_to_string(input_path)?;
    let archive: ExportArchive = serde_json::from_str(&content)
        .map_err(|e| Error::Io(std::io::Error::new(std::io::ErrorKind::InvalidData, e)))?;

    let mut imported = 0;
    for exp in archive.notes {
        let mut note = store.create()?;
        note.title = exp.title;
        note.content = exp.content;
        note.priority = exp.priority;
        note.is_pinned = exp.is_pinned;
        note.is_archived = exp.is_archived;
        note.tags = exp.tags;
        store.update(&note)?;
        imported += 1;
    }

    Ok(imported)
}

pub fn import_note_markdown_file(store: &NoteStore, input_path: &Path) -> Result<usize> {
    let raw = fs::read_to_string(input_path)?;
    let (title, content, tags) = parse_markdown_note(&raw, input_path);

    let mut note = store.create()?;
    note.title = title;
    note.content = content;
    note.tags = tags;
    store.update(&note)?;
    Ok(1)
}

fn parse_markdown_note(raw: &str, path: &Path) -> (String, String, Vec<String>) {
    let default_title = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Imported note")
        .to_string();

    if let Some(stripped) = raw.strip_prefix("---") {
        if let Some(end_idx) = stripped.find("---") {
            let frontmatter = &stripped[..end_idx];
            let body = stripped[end_idx + 3..]
                .trim_start_matches(['\r', '\n'])
                .to_string();

            let mut title = default_title.clone();
            let mut tags = Vec::new();

            for line in frontmatter.lines() {
                let trimmed = line.trim();
                if let Some(val) = trimmed.strip_prefix("title:") {
                    let cleaned = val.trim().trim_matches('"').trim_matches('\'').to_string();
                    if !cleaned.is_empty() {
                        title = cleaned;
                    }
                } else if let Some(val) = trimmed.strip_prefix("tags:") {
                    let tags_str = val.trim().trim_matches('[').trim_matches(']');
                    tags = tags_str
                        .split(',')
                        .map(|s| s.trim().trim_matches('"').trim_matches('\'').to_string())
                        .filter(|s| !s.is_empty())
                        .collect();
                }
            }
            return (title, body, tags);
        }
    }

    // If starts with '# Title'
    if let Some(rest) = raw.strip_prefix("# ") {
        if let Some((first_line, remaining)) = rest.split_once('\n') {
            let title = first_line.trim().to_string();
            let body = remaining.trim().to_string();
            return (title, body, Vec::new());
        }
    }

    (default_title, raw.to_string(), Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_frontmatter_markdown() {
        let md = "---\ntitle: \"Meeting notes\"\ntags: [work, plan]\n---\nHello team!";
        let path = Path::new("dummy.md");
        let (title, content, tags) = parse_markdown_note(md, path);
        assert_eq!(title, "Meeting notes");
        assert_eq!(content, "Hello team!");
        assert_eq!(tags, vec!["work", "plan"]);
    }

    #[test]
    fn parse_heading_markdown() {
        let md = "# Project ideas\n1. Idea A\n2. Idea B";
        let path = Path::new("dummy.md");
        let (title, content, tags) = parse_markdown_note(md, path);
        assert_eq!(title, "Project ideas");
        assert_eq!(content, "1. Idea A\n2. Idea B");
        assert!(tags.is_empty());
    }
}
