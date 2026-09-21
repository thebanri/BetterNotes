//! Notes from files opened with BetterNotes ("Open with" in a file manager,
//! or `betternotes --open FILE...`): a text or Markdown file becomes a note
//! with its text, an image a note showing the image.
//!
//! Paths arrive from the command line or over IPC and are untrusted: only
//! absolute paths to regular files of a supported kind and bounded size are
//! read, and nothing is ever executed.

use crate::{attachments, export_import, Error, NoteStore, Result};
use std::{
    fs,
    path::{Path, PathBuf},
};

/// At most this many files are taken from one request.
pub const MAX_FILES: usize = 20;
const MAX_TEXT_BYTES: u64 = 5 * 1024 * 1024;
const MAX_IMAGE_BYTES: u64 = 50 * 1024 * 1024;
const IMAGE_EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"];
const MARKDOWN_EXTENSIONS: &[&str] = &["md", "markdown", "mdown", "mkd"];
/// Width an opened image is shown at in its note; it can be resized there.
const IMAGE_WIDTH: u32 = 320;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    Markdown,
    Text,
    Image,
}

/// What kind of note a file makes, or why it cannot be opened.
pub fn classify(path: &Path) -> Result<FileKind> {
    let refuse = |reason: &str| {
        Err(Error::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            reason.to_string(),
        )))
    };
    if !path.is_absolute() {
        return refuse("not an absolute path");
    }
    let metadata = fs::metadata(path)?;
    if !metadata.is_file() {
        return refuse("not a regular file");
    }
    let extension = path
        .extension()
        .and_then(|extension| extension.to_str())
        .unwrap_or_default()
        .to_lowercase();
    let (kind, limit) = if IMAGE_EXTENSIONS.contains(&extension.as_str()) {
        (FileKind::Image, MAX_IMAGE_BYTES)
    } else if MARKDOWN_EXTENSIONS.contains(&extension.as_str()) {
        (FileKind::Markdown, MAX_TEXT_BYTES)
    } else {
        (FileKind::Text, MAX_TEXT_BYTES)
    };
    if metadata.len() > limit {
        return refuse("too large to open as a note");
    }
    Ok(kind)
}

/// Creates a note from one file and returns its id.
pub fn note_from_file(store: &NoteStore, data_dir: &Path, path: &Path) -> Result<i64> {
    let kind = classify(path)?;
    let title = path
        .file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("Opened file")
        .to_string();
    match kind {
        FileKind::Markdown => {
            let before = store.list()?.iter().map(|note| note.id).max().unwrap_or(0);
            export_import::import_note_markdown_file(store, path)?;
            store
                .list()?
                .iter()
                .map(|note| note.id)
                .filter(|&id| id > before)
                .max()
                .ok_or(Error::NoSelection)
        }
        FileKind::Text => {
            let bytes = fs::read(path)?;
            // Text that is not UTF-8 is read as well as it can be, not refused.
            let text = String::from_utf8_lossy(&bytes).into_owned();
            let mut note = store.create()?;
            note.title = title;
            note.content = text;
            Ok(store.update(&note)?.id)
        }
        FileKind::Image => {
            let mut note = store.create()?;
            let attachment =
                attachments::add_attachment(data_dir, store.raw_connection(), note.id, path)?;
            let url = file_url(&attachments::stored_path(data_dir, &attachment));
            note.title = title;
            note.content = format!(
                "<html><body><p><img src=\"{url}\" width=\"{IMAGE_WIDTH}\" /></p></body></html>"
            );
            Ok(store.update(&note)?.id)
        }
    }
}

/// Paths from the command line or IPC, made absolute and limited in number.
pub fn requested_paths<I, S>(arguments: I, working_dir: &Path) -> Vec<PathBuf>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    arguments
        .into_iter()
        .filter_map(|argument| {
            let argument = argument.as_ref();
            let path = argument.strip_prefix("file://").unwrap_or(argument);
            (!path.is_empty()).then(|| working_dir.join(percent_decode(path)))
        })
        .take(MAX_FILES)
        .collect()
}

/// A file:// URL for a local path, percent-encoding everything but the
/// characters that are safe in a path.
fn file_url(path: &Path) -> String {
    let mut url = String::from("file://");
    for byte in path.to_string_lossy().bytes() {
        if byte.is_ascii_alphanumeric() || b"/-._~".contains(&byte) {
            url.push(byte as char);
        } else {
            url.push_str(&format!("%{byte:02X}"));
        }
    }
    url
}

fn percent_decode(text: &str) -> String {
    let hex = |byte: u8| (byte as char).to_digit(16).map(|digit| digit as u8);
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(high), Some(low)) = (hex(bytes[i + 1]), hex(bytes[i + 2])) {
                out.push(high * 16 + low);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_and_refuses_files() {
        let dir = tempfile::tempdir().unwrap();
        let text = dir.path().join("list.txt");
        let markdown = dir.path().join("plan.MD");
        let image = dir.path().join("cat.png");
        fs::write(&text, "a").unwrap();
        fs::write(&markdown, "# Plan").unwrap();
        fs::write(&image, "png").unwrap();
        assert_eq!(classify(&text).unwrap(), FileKind::Text);
        assert_eq!(classify(&markdown).unwrap(), FileKind::Markdown);
        assert_eq!(classify(&image).unwrap(), FileKind::Image);
        assert!(classify(dir.path()).is_err(), "a directory");
        assert!(classify(Path::new("relative.txt")).is_err());
        assert!(classify(&dir.path().join("missing.txt")).is_err());
        let big = dir.path().join("big.txt");
        let file = fs::File::create(&big).unwrap();
        file.set_len(MAX_TEXT_BYTES + 1).unwrap();
        assert!(classify(&big).is_err());
    }

    #[test]
    fn opened_files_become_notes() {
        let dir = tempfile::tempdir().unwrap();
        let store = NoteStore::open(&dir.path().join("notes.sqlite3")).unwrap();
        let text = dir.path().join("shopping list.txt");
        fs::write(&text, "milk\neggs").unwrap();
        let id = note_from_file(&store, dir.path(), &text).unwrap();
        let note = store.get(id).unwrap();
        assert_eq!(note.title, "shopping list");
        assert_eq!(note.content, "milk\neggs");

        let markdown = dir.path().join("plan.md");
        fs::write(&markdown, "---\ntitle: The plan\n---\nStep one").unwrap();
        let id = note_from_file(&store, dir.path(), &markdown).unwrap();
        assert_eq!(store.get(id).unwrap().title, "The plan");

        let image = dir.path().join("my cat.png");
        fs::write(&image, "png").unwrap();
        let id = note_from_file(&store, dir.path(), &image).unwrap();
        let note = store.get(id).unwrap();
        assert_eq!(note.title, "my cat");
        assert!(note.content.contains("<img src=\"file://"));
        assert!(note.content.contains("my_cat.png"));
        assert_eq!(
            attachments::list_attachments(store.raw_connection(), id)
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn requested_paths_are_absolute_decoded_and_bounded() {
        let paths = requested_paths(
            ["notes.txt", "file:///tmp/my%20file.md", "/abs/x.png", ""],
            Path::new("/work"),
        );
        assert_eq!(
            paths,
            [
                PathBuf::from("/work/notes.txt"),
                PathBuf::from("/tmp/my file.md"),
                PathBuf::from("/abs/x.png"),
            ]
        );
        let many: Vec<String> = (0..50).map(|i| format!("/f{i}")).collect();
        assert_eq!(requested_paths(&many, Path::new("/")).len(), MAX_FILES);
        assert_eq!(
            file_url(Path::new("/home/a b/ç.png")),
            "file:///home/a%20b/%C3%A7.png"
        );
    }
}
