//! Qt-independent notes, persistence and editor state.

pub mod autostart;
mod notes;
pub mod notifications;
pub mod paths;
mod session;
pub mod settings;
pub mod shortcuts;
mod store;
mod window_state;

pub use autostart::{is_autostart_enabled, set_autostart};
pub use notes::{Error, Note, NoteSummary, Result, SearchResult};
pub use notifications::NotificationService;
pub use session::NotesSession;
pub use settings::ThemePreference;
pub use shortcuts::GlobalShortcutService;
pub use store::NoteStore;
pub use window_state::WindowState;

/// Development codename, not a final product name.
pub const APPLICATION_NAME: &str = "BetterNotes";
pub const APPLICATION_VERSION: &str = env!("CARGO_PKG_VERSION");
