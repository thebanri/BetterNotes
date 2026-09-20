//! Qt-independent notes, persistence and editor state.

mod notes;
pub mod paths;
mod session;
pub mod settings;
mod store;
mod window_state;

pub use notes::{Error, Note, NoteSummary, Result};
pub use session::NotesSession;
pub use settings::ThemePreference;
pub use store::NoteStore;
pub use window_state::WindowState;

/// Development codename, not a final product name.
pub const APPLICATION_NAME: &str = "BetterNotes";
pub const APPLICATION_VERSION: &str = env!("CARGO_PKG_VERSION");
