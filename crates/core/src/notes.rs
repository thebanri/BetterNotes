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
}

/// List queries deliberately omit note bodies.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NoteSummary {
    pub id: i64,
    pub title: String,
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
}

pub type Result<T> = std::result::Result<T, Error>;
