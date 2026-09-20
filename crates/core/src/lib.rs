//! Qt-independent notes, persistence and editor state.

mod notes;
pub mod paths;
mod session;
mod store;

pub use notes::{Error, Note, NoteSummary, Result};
pub use session::NotesSession;
pub use store::NoteStore;

/// Development codename, not a final product name.
pub const APPLICATION_NAME: &str = "BetterNotes";
pub const APPLICATION_VERSION: &str = env!("CARGO_PKG_VERSION");
