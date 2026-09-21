use thiserror::Error;

/// Timestamps are Unix milliseconds. Revision prevents silent concurrent overwrites.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Note {
    pub id: i64,
    pub title: String,
    pub content: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub revision: i64,
    pub priority: i32,
    pub is_archived: bool,
    pub is_pinned: bool,
    pub tags: Vec<String>,
    /// Content is sealed with the master password (see vault).
    pub is_locked: bool,
}

/// List queries deliberately omit note bodies, providing summaries with snippets and metadata.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteSummary {
    pub id: i64,
    pub title: String,
    pub snippet: String,
    pub priority: i32,
    pub is_archived: bool,
    pub is_pinned: bool,
    pub tags: Vec<String>,
    pub is_locked: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SearchResult {
    pub id: i64,
    pub title: String,
    pub snippet: String,
}

#[derive(Debug, Error)]
pub enum Error {
    #[error("Database operation failed: {0}")]
    Database(#[from] rusqlite::Error),
    #[error("Filesystem operation failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("Database schema version {0} is unsupported. Use a compatible application version.")]
    UnsupportedSchema(i64),
    #[error("This database is not a recognized BetterNotes database. It was left intact.")]
    UnrecognizedDatabase,
    #[error("Note {0} no longer exists. Reload the notes list.")]
    NotFound(i64),
    #[error("This note was changed or deleted by another process. Copy any unsaved text before reloading.")]
    Conflict,
    #[error("No note is selected.")]
    NoSelection,
    #[error("The selected note is not in the list.")]
    InvalidSelection,
    #[error("Cannot determine an absolute data directory from XDG_DATA_HOME or HOME.")]
    MissingDataDirectory,
    #[error("The system clock cannot be represented as Unix milliseconds.")]
    Clock,
    #[error("The note revision limit was reached.")]
    RevisionOverflow,
    #[error("The saved window geometry is invalid. The note has not been changed.")]
    InvalidWindowState,
    #[error("IPC communication error: {0}")]
    Ipc(String),
    #[error("Serialization error: {0}")]
    Serialization(String),
    #[error("{0}")]
    Install(String),
    #[error("Choose a valid date and time for the reminder.")]
    InvalidReminder,
    #[error("This note is locked. Unlock locked notes with your password first.")]
    Locked,
}

pub type Result<T> = std::result::Result<T, Error>;
