//! Qt-independent notes, persistence and editor state.

pub mod attachments;
pub mod autostart;
pub mod backup;
pub mod desktop;
pub mod export_import;
pub mod install;
pub mod ipc;
pub mod links;
mod notes;
pub mod notifications;
pub mod paths;
pub mod preview;
pub mod reminders;
mod session;
pub mod settings;
pub mod shortcuts;
mod store;
mod window_state;

pub use attachments::{add_attachment, delete_attachment, list_attachments, Attachment};
pub use autostart::{is_autostart_enabled, set_autostart};
pub use backup::{create_backup, restore_backup, BackupManifest};
pub use desktop::{DesktopEnvironment, DesktopReport, DisplayServer};
pub use export_import::{
    export_notes_json, export_notes_markdown_dir, import_note_markdown_file, import_notes_json,
    ExportArchive, ExportNote,
};
pub use ipc::{
    global_ipc_queue, handle_domain_request, is_server_running, send_request, IpcAction,
    IpcRequest, IpcResponse, IpcServer, SharedIpcQueue,
};
pub use links::external_url;
pub use notes::{Error, Note, NoteSummary, Result, SearchResult};
pub use notifications::NotificationService;
pub use preview::{plain_preview, to_plain_text};
pub use reminders::{
    clear_reminder_for_note, dismiss_or_advance_reminder, get_due_reminders, get_reminder_for_note,
    set_reminder, DueReminder, Recurrence, Reminder,
};
pub use session::NotesSession;
pub use settings::ThemePreference;
pub use shortcuts::GlobalShortcutService;
pub use store::NoteStore;
pub use window_state::WindowState;

/// Development codename, not a final product name.
pub const APPLICATION_NAME: &str = "BetterNotes";
/// Reverse-DNS application id: the desktop entry, icon and metainfo names, the
/// Wayland app_id and the session-bus name prefix.
pub const APPLICATION_ID: &str = "org.betternotes.BetterNotes";
pub const APPLICATION_VERSION: &str = env!("CARGO_PKG_VERSION");
