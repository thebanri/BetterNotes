#![allow(clippy::too_many_arguments)]
//! Qt adapter for the independent Rust editing session. No SQL or note rules in QML.
use betternotes_core::{paths, Error, NotesSession, Result, ThemePreference, WindowState};
use cxx_qt::CxxQtType;
use cxx_qt_lib::{QString, QStringList, QUrl};
use std::pin::Pin;

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("platform_helper.h");
        fn platformCopyToClipboard(text: &QString);
        fn platformGetClipboardText() -> QString;
        fn platformCursorGlobalX() -> i32;
        fn platformCursorGlobalY() -> i32;
        fn platformSetApplicationIcon() -> bool;
        fn platformPicturesFolder() -> QString;
        fn platformDocumentsFolder() -> QString;
        fn platformClipboardImageToFile() -> QString;
        fn platformClipboardImageUrls() -> QString;
    }
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QStringList, titles, READ, NOTIFY = list_changed)]
        #[qproperty(QStringList, note_ids, READ, NOTIFY = list_changed, cxx_name = "noteIds")]
        #[qproperty(QStringList, snippets, READ, NOTIFY = list_changed)]
        #[qproperty(QStringList, pinned_states, READ, NOTIFY = list_changed, cxx_name = "pinnedStates")]
        #[qproperty(QStringList, archived_states, READ, NOTIFY = list_changed, cxx_name = "archivedStates")]
        #[qproperty(QStringList, priorities, READ, NOTIFY = list_changed)]
        #[qproperty(QStringList, note_tags, READ, NOTIFY = list_changed, cxx_name = "noteTags")]
        #[qproperty(QStringList, note_colors, READ, NOTIFY = list_changed, cxx_name = "noteColors")]
        #[qproperty(QStringList, trash_ids, READ, NOTIFY = list_changed, cxx_name = "trashIds")]
        #[qproperty(QStringList, trash_titles, READ, NOTIFY = list_changed, cxx_name = "trashTitles")]
        #[qproperty(QStringList, trash_snippets, READ, NOTIFY = list_changed, cxx_name = "trashSnippets")]
        /// When each trashed note was deleted, in Unix milliseconds.
        #[qproperty(QStringList, trash_deleted_at, READ, NOTIFY = list_changed, cxx_name = "trashDeletedAt")]
        /// Per listed note: "<unix seconds>|<recurrence>" or "" without a reminder.
        #[qproperty(QStringList, note_reminders, READ, NOTIFY = list_changed, cxx_name = "noteReminders")]
        #[qproperty(QStringList, all_tags, READ, NOTIFY = list_changed, cxx_name = "allTags")]
        #[qproperty(QStringList, restore_ids, READ, NOTIFY = list_changed, cxx_name = "restoreIds")]
        #[qproperty(QString, current_id, READ, NOTIFY = selection_changed, cxx_name = "currentId")]
        #[qproperty(i32, current_index, READ, NOTIFY = selection_changed, cxx_name = "currentIndex")]
        #[qproperty(QString, draft_title, READ, NOTIFY = selection_changed, cxx_name = "draftTitle")]
        #[qproperty(QString, draft_content, READ, NOTIFY = selection_changed, cxx_name = "draftContent")]
        #[qproperty(bool, is_pinned, READ, NOTIFY = selection_changed, cxx_name = "isPinned")]
        #[qproperty(bool, is_archived, READ, NOTIFY = selection_changed, cxx_name = "isArchived")]
        #[qproperty(i32, priority, READ, NOTIFY = selection_changed)]
        #[qproperty(QStringList, tags, READ, NOTIFY = selection_changed)]
        #[qproperty(QString, tags_text, READ, NOTIFY = selection_changed, cxx_name = "tagsText")]
        #[qproperty(QStringList, search_result_ids, READ, NOTIFY = search_changed, cxx_name = "searchResultIds")]
        #[qproperty(QStringList, search_result_titles, READ, NOTIFY = search_changed, cxx_name = "searchResultTitles")]
        #[qproperty(QStringList, search_result_snippets, READ, NOTIFY = search_changed, cxx_name = "searchResultSnippets")]
        #[qproperty(bool, ready, READ, NOTIFY = status_changed)]
        #[qproperty(bool, dirty, READ, NOTIFY = status_changed)]
        #[qproperty(QString, error_message, READ, NOTIFY = status_changed, cxx_name = "errorMessage")]
        #[qproperty(QString, window_error, READ, NOTIFY = status_changed, cxx_name = "windowError")]
        #[qproperty(QString, theme_mode, READ, NOTIFY = theme_changed, cxx_name = "themeMode")]
        #[qproperty(bool, autostart_enabled, READ, NOTIFY = autostart_changed, cxx_name = "autostartEnabled")]
        #[qproperty(bool, notes_stay_below, READ, NOTIFY = layer_changed, cxx_name = "notesStayBelow")]
        #[qproperty(QString, accent_color, READ, NOTIFY = theme_changed, cxx_name = "accentColor")]
        /// Per listed note: "true" when its content is locked.
        #[qproperty(QStringList, locked_states, READ, NOTIFY = list_changed, cxx_name = "lockedStates")]
        /// The selected note is locked.
        #[qproperty(bool, is_locked, READ, NOTIFY = list_changed, cxx_name = "isLocked")]
        /// A master password exists, and whether it is unlocked right now.
        #[qproperty(bool, vault_set, READ, NOTIFY = list_changed, cxx_name = "vaultSet")]
        #[qproperty(bool, vault_unlocked, READ, NOTIFY = list_changed, cxx_name = "vaultUnlocked")]
        /// Every configurable shortcut as a JSON object {action: sequence}.
        #[qproperty(QString, shortcuts_json, READ, NOTIFY = theme_changed, cxx_name = "shortcutsJson")]
        type NotesBackend = super::NotesBackendRust;

        #[qsignal]
        fn list_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn selection_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn status_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn theme_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn search_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn autostart_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn layer_changed(self: Pin<&mut Self>);

        #[qinvokable]
        fn initialize(self: Pin<&mut Self>) -> bool;
        #[qinvokable]
        #[cxx_name = "initializeNote"]
        fn initialize_note(self: Pin<&mut Self>, id: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "reloadNote"]
        fn reload_note(self: Pin<&mut Self>) -> bool;
        #[qinvokable]
        #[cxx_name = "saveWindow"]
        fn save_window(
            self: Pin<&mut Self>,
            x: i32,
            y: i32,
            width: i32,
            height: i32,
            screen: QString,
            collapsed: bool,
            positioned: bool,
            open: bool,
        ) -> bool;
        #[qinvokable]
        #[cxx_name = "savedX"]
        fn saved_x(&self) -> i32;
        #[qinvokable]
        #[cxx_name = "savedY"]
        fn saved_y(&self) -> i32;
        #[qinvokable]
        #[cxx_name = "savedWidth"]
        fn saved_width(&self) -> i32;
        #[qinvokable]
        #[cxx_name = "savedHeight"]
        fn saved_height(&self) -> i32;
        #[qinvokable]
        #[cxx_name = "savedScreen"]
        fn saved_screen(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "savedCollapsed"]
        fn saved_collapsed(&self) -> bool;
        #[qinvokable]
        #[cxx_name = "savedPositioned"]
        fn saved_positioned(&self) -> bool;
        #[qinvokable]
        #[cxx_name = "createNote"]
        fn create_note(self: Pin<&mut Self>) -> bool;
        #[qinvokable]
        #[cxx_name = "selectNote"]
        fn select_note(self: Pin<&mut Self>, index: i32) -> bool;
        #[qinvokable]
        #[cxx_name = "deleteNote"]
        fn delete_note(self: Pin<&mut Self>) -> bool;
        #[qinvokable]
        fn reload(self: Pin<&mut Self>) -> bool;
        #[qinvokable]
        fn save(self: Pin<&mut Self>) -> bool;
        #[qinvokable]
        #[cxx_name = "editTitle"]
        fn edit_title(self: Pin<&mut Self>, title: QString);
        #[qinvokable]
        #[cxx_name = "editContent"]
        fn edit_content(self: Pin<&mut Self>, content: QString);
        #[qinvokable]
        #[cxx_name = "setThemeMode"]
        fn set_theme_mode(self: Pin<&mut Self>, mode: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "setNotePinned"]
        fn set_note_pinned(self: Pin<&mut Self>, id: QString, pinned: bool) -> bool;
        #[qinvokable]
        #[cxx_name = "setNoteArchived"]
        fn set_note_archived(self: Pin<&mut Self>, id: QString, archived: bool) -> bool;
        #[qinvokable]
        #[cxx_name = "deleteNoteById"]
        fn delete_note_by_id(self: Pin<&mut Self>, id: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "restoreNote"]
        fn restore_note(self: Pin<&mut Self>, id: QString) -> bool;
        /// Deletes a note in the trash for good.
        #[qinvokable]
        #[cxx_name = "deleteForever"]
        fn delete_forever(self: Pin<&mut Self>, id: QString) -> bool;
        /// Deletes every note in the trash for good; returns how many, or -1.
        #[qinvokable]
        #[cxx_name = "emptyTrash"]
        fn empty_trash(self: Pin<&mut Self>) -> i32;
        #[qinvokable]
        #[cxx_name = "addNoteTag"]
        fn add_note_tag(self: Pin<&mut Self>, id: QString, tag: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "notePlainText"]
        fn note_plain_text(&self, id: QString) -> QString;
        #[qinvokable]
        #[cxx_name = "setNotesStayBelow"]
        fn set_notes_stay_below(self: Pin<&mut Self>, enabled: bool) -> bool;
        #[qinvokable]
        fn search(self: Pin<&mut Self>, query: QString);
        #[qinvokable]
        #[cxx_name = "setPinned"]
        fn set_pinned(self: Pin<&mut Self>, pinned: bool) -> bool;
        #[qinvokable]
        #[cxx_name = "setArchived"]
        fn set_archived(self: Pin<&mut Self>, archived: bool) -> bool;
        #[qinvokable]
        #[cxx_name = "setPriority"]
        fn set_priority(self: Pin<&mut Self>, priority: i32) -> bool;
        #[qinvokable]
        #[cxx_name = "setTags"]
        fn set_tags(self: Pin<&mut Self>, tags: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "noteColor"]
        fn note_color(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "setNoteColor"]
        fn set_note_color(self: Pin<&mut Self>, color: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "noteFontFamily"]
        fn note_font_family(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "setNoteFontFamily"]
        fn set_note_font_family(self: Pin<&mut Self>, family: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "noteFontSize"]
        fn note_font_size(&self) -> i32;
        #[qinvokable]
        #[cxx_name = "setNoteFontSize"]
        fn set_note_font_size(self: Pin<&mut Self>, size: i32) -> bool;
        /// Saves a copy of a note image (file URL) to a chosen file URL.
        #[qinvokable]
        #[cxx_name = "saveImageAs"]
        fn save_image_as(self: Pin<&mut Self>, image_url: QString, target_url: QString) -> bool;
        /// The file name an image had before it was attached.
        #[qinvokable]
        #[cxx_name = "imageFileName"]
        fn image_file_name(&self, image_url: QString) -> QString;
        #[qinvokable]
        #[cxx_name = "picturesFolder"]
        fn pictures_folder(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "documentsFolder"]
        fn documents_folder(&self) -> QString;
        /// Attaches an image on the clipboard to the note and returns its
        /// file URL, or "" when the clipboard holds no image data.
        /// The note's file attachments (not its inline images) as a JSON
        /// array of {id, name, size, url, openable}.
        #[qinvokable]
        #[cxx_name = "attachmentsJson"]
        fn attachments_json(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "attachFile"]
        fn attach_file(self: Pin<&mut Self>, file_url: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "removeAttachment"]
        fn remove_attachment(self: Pin<&mut Self>, id: QString) -> bool;
        /// The URL to open an attachment with, or "" when it must not be
        /// opened because it could run code.
        #[qinvokable]
        #[cxx_name = "attachmentOpenUrl"]
        fn attachment_open_url(&self, id: QString) -> QString;
        #[qinvokable]
        #[cxx_name = "pasteClipboardImage"]
        fn paste_clipboard_image(self: Pin<&mut Self>) -> QString;
        /// Local file URLs on the clipboard, newline-separated.
        #[qinvokable]
        #[cxx_name = "clipboardFileUrls"]
        fn clipboard_file_urls(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "attachImage"]
        fn attach_image(self: Pin<&mut Self>, file_url: QString) -> QString;
        #[qinvokable]
        #[cxx_name = "setAutostart"]
        fn set_autostart(self: Pin<&mut Self>, enabled: bool) -> bool;
        #[qinvokable]
        #[cxx_name = "copyToClipboard"]
        fn copy_to_clipboard(self: Pin<&mut Self>, text: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "getClipboardText"]
        fn get_clipboard_text(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "cursorGlobalX"]
        fn cursor_global_x(&self) -> i32;
        #[qinvokable]
        #[cxx_name = "cursorGlobalY"]
        fn cursor_global_y(&self) -> i32;
        #[qinvokable]
        #[cxx_name = "sendNotification"]
        fn send_notification(self: Pin<&mut Self>, title: QString, body: QString) -> bool;

        #[qinvokable]
        #[cxx_name = "setReminder"]
        fn set_reminder(self: Pin<&mut Self>, timestamp_sec: i64, recurrence: QString) -> bool;

        #[qinvokable]
        #[cxx_name = "clearReminder"]
        fn clear_reminder(self: Pin<&mut Self>) -> bool;

        #[qinvokable]
        #[cxx_name = "checkReminders"]
        fn check_reminders(self: Pin<&mut Self>) -> i32;

        /// The words reminder notifications use, in the interface language:
        /// the body text and the Open and Snooze button labels.
        #[qinvokable]
        #[cxx_name = "setReminderTexts"]
        fn set_reminder_texts(
            self: Pin<&mut Self>,
            body: QString,
            open_label: QString,
            snooze_label: QString,
        );

        /// A note's reminder as "<unix seconds>|<recurrence>", or "".
        #[qinvokable]
        #[cxx_name = "noteReminder"]
        fn note_reminder(&self, id: QString) -> QString;

        /// Sets any note's reminder by id, e.g. from the library.
        #[qinvokable]
        #[cxx_name = "setNoteReminder"]
        fn set_note_reminder(
            self: Pin<&mut Self>,
            id: QString,
            timestamp_sec: i64,
            recurrence: QString,
        ) -> bool;

        #[qinvokable]
        #[cxx_name = "clearNoteReminder"]
        fn clear_note_reminder(self: Pin<&mut Self>, id: QString) -> bool;

        #[qinvokable]
        #[cxx_name = "exportNotesJson"]
        fn export_notes_json(self: Pin<&mut Self>, file_path: QString) -> bool;

        #[qinvokable]
        #[cxx_name = "exportNotesMarkdown"]
        fn export_notes_markdown(self: Pin<&mut Self>, dir_path: QString) -> bool;

        #[qinvokable]
        #[cxx_name = "importNotesJson"]
        fn import_notes_json(self: Pin<&mut Self>, file_path: QString) -> i32;

        #[qinvokable]
        #[cxx_name = "importNoteMarkdown"]
        fn import_note_markdown(self: Pin<&mut Self>, file_path: QString) -> i32;

        /// Recent library searches, newest first.
        #[qinvokable]
        #[cxx_name = "recentSearches"]
        fn recent_searches(&self) -> QStringList;

        #[qinvokable]
        #[cxx_name = "rememberSearch"]
        fn remember_search(self: Pin<&mut Self>, query: QString);

        #[qinvokable]
        #[cxx_name = "clearRecentSearches"]
        fn clear_recent_searches(self: Pin<&mut Self>);

        /// Creates a note from each file (text, Markdown or image) and
        /// returns the new note ids; files that cannot be opened are skipped
        /// and reported in errorMessage.
        #[qinvokable]
        #[cxx_name = "openFiles"]
        fn open_files(self: Pin<&mut Self>, paths: QStringList) -> QStringList;

        /// Automatic backup settings as JSON: {enabled, interval, keep,
        /// folder, target, last}.
        #[qinvokable]
        #[cxx_name = "autoBackupSettings"]
        fn auto_backup_settings(&self) -> QString;
        #[qinvokable]
        #[cxx_name = "setAutoBackupSettings"]
        fn set_auto_backup_settings(
            self: Pin<&mut Self>,
            enabled: bool,
            interval: QString,
            keep: i32,
            folder: QString,
        ) -> bool;
        /// Backs up now; returns the backup folder, or "" (see errorMessage).
        #[qinvokable]
        #[cxx_name = "backupNow"]
        fn backup_now(self: Pin<&mut Self>) -> QString;
        /// Makes an automatic backup if one is due, in the background.
        #[qinvokable]
        #[cxx_name = "runAutoBackup"]
        fn run_auto_backup(&self);

        /// Sets the master password the first time; returns "" or why not.
        #[qinvokable]
        #[cxx_name = "setUpPassword"]
        fn set_up_password(self: Pin<&mut Self>, password: QString) -> QString;
        /// Unlocks locked notes; false for a wrong password.
        #[qinvokable]
        #[cxx_name = "unlockNotes"]
        fn unlock_notes(self: Pin<&mut Self>, password: QString) -> bool;
        #[qinvokable]
        #[cxx_name = "lockNotes"]
        fn lock_notes(self: Pin<&mut Self>);
        #[qinvokable]
        #[cxx_name = "changePassword"]
        fn change_password(self: Pin<&mut Self>, current: QString, replacement: QString)
            -> QString;
        /// Locks or unlocks the selected note's content.
        #[qinvokable]
        #[cxx_name = "setLocked"]
        fn set_locked(self: Pin<&mut Self>, locked: bool) -> bool;
        #[qinvokable]
        #[cxx_name = "setNoteLocked"]
        fn set_note_locked(self: Pin<&mut Self>, id: QString, locked: bool) -> bool;
        /// Rereads the lists and vault state, e.g. after another window
        /// unlocked or locked notes.
        #[qinvokable]
        #[cxx_name = "refreshState"]
        fn refresh_state(self: Pin<&mut Self>);

        #[qinvokable]
        #[cxx_name = "setAccentColor"]
        fn set_accent_color(self: Pin<&mut Self>, color: QString) -> bool;
        /// Sets a shortcut; returns "" or why it was refused.
        #[qinvokable]
        #[cxx_name = "setShortcut"]
        fn set_shortcut(self: Pin<&mut Self>, action: QString, sequence: QString) -> QString;
        #[qinvokable]
        #[cxx_name = "resetShortcuts"]
        fn reset_shortcuts(self: Pin<&mut Self>) -> bool;

        #[qinvokable]
        #[cxx_name = "pollIpcAction"]
        fn poll_ipc_action(self: Pin<&mut Self>) -> QString;
    }
}

fn data_directory() -> Result<std::path::PathBuf> {
    paths::data_directory(
        std::env::var_os("XDG_DATA_HOME").as_deref(),
        std::env::var_os("HOME").as_deref(),
    )
}

/// A path from QML, which passes file dialog results as file URLs.
fn local_path(path_or_url: &QString) -> String {
    match QUrl::from(path_or_url).to_local_file() {
        Some(path) if path_or_url.to_string().starts_with("file:") => path.to_string(),
        _ => path_or_url.to_string(),
    }
}

pub struct NotesBackendRust {
    session: Option<NotesSession>,
    titles: QStringList,
    note_ids: QStringList,
    snippets: QStringList,
    pinned_states: QStringList,
    archived_states: QStringList,
    priorities: QStringList,
    note_tags: QStringList,
    note_colors: QStringList,
    note_reminders: QStringList,
    accent_color: QString,
    locked_states: QStringList,
    is_locked: bool,
    vault_set: bool,
    vault_unlocked: bool,
    shortcuts_json: QString,
    reminder_texts: [String; 3],
    trash_ids: QStringList,
    trash_titles: QStringList,
    trash_snippets: QStringList,
    trash_deleted_at: QStringList,
    all_tags: QStringList,
    restore_ids: QStringList,
    current_id: QString,
    current_index: i32,
    draft_title: QString,
    draft_content: QString,
    is_pinned: bool,
    is_archived: bool,
    priority: i32,
    tags: QStringList,
    tags_text: QString,
    search_result_ids: QStringList,
    search_result_titles: QStringList,
    search_result_snippets: QStringList,
    ready: bool,
    dirty: bool,
    error_message: QString,
    window_error: QString,
    window_state: WindowState,
    theme_mode: QString,
    autostart_enabled: bool,
    notes_stay_below: bool,
}

impl Default for NotesBackendRust {
    fn default() -> Self {
        Self {
            session: None,
            titles: QStringList::default(),
            note_ids: QStringList::default(),
            snippets: QStringList::default(),
            pinned_states: QStringList::default(),
            archived_states: QStringList::default(),
            priorities: QStringList::default(),
            note_tags: QStringList::default(),
            note_colors: QStringList::default(),
            note_reminders: QStringList::default(),
            accent_color: QString::from(betternotes_core::settings::DEFAULT_ACCENT),
            locked_states: QStringList::default(),
            is_locked: false,
            vault_set: false,
            vault_unlocked: false,
            shortcuts_json: QString::default(),
            reminder_texts: [
                "Reminder from BetterNotes".into(),
                "Open note".into(),
                "Snooze 10 min".into(),
            ],
            trash_ids: QStringList::default(),
            trash_titles: QStringList::default(),
            trash_snippets: QStringList::default(),
            trash_deleted_at: QStringList::default(),
            all_tags: QStringList::default(),
            restore_ids: QStringList::default(),
            current_id: QString::default(),
            current_index: -1,
            draft_title: QString::default(),
            draft_content: QString::default(),
            is_pinned: false,
            is_archived: false,
            priority: 0,
            tags: QStringList::default(),
            tags_text: QString::default(),
            search_result_ids: QStringList::default(),
            search_result_titles: QStringList::default(),
            search_result_snippets: QStringList::default(),
            ready: false,
            dirty: false,
            error_message: QString::default(),
            window_error: QString::default(),
            window_state: WindowState::default(),
            theme_mode: QString::from("system"),
            autostart_enabled: false,
            notes_stay_below: true,
        }
    }
}

impl ffi::NotesBackend {
    pub fn initialize(mut self: Pin<&mut Self>) -> bool {
        if self.ready {
            return true;
        }
        let result = paths::database_path().and_then(|path| {
            let mut session = NotesSession::open(&path)?;
            // Notes leave the trash for good after 30 days.
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|elapsed| elapsed.as_millis() as i64)
                .unwrap_or(0);
            if let Err(error) =
                session.empty_trash(Some(now - betternotes_core::TRASH_RETENTION_MS))
            {
                eprintln!("BetterNotes: could not empty old notes from the trash: {error}");
            }
            let ids = session.open_window_ids()?;
            Ok((session, ids))
        });
        match result {
            Ok((session, ids)) => {
                self.as_mut().rust_mut().restore_ids = ids
                    .iter()
                    .map(|id| QString::from(&id.to_string()))
                    .collect();
                self.as_mut().rust_mut().session = Some(session);
                self.as_mut().rust_mut().ready = true;
                self.finish(Ok(()), true)
            }
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn initialize_note(mut self: Pin<&mut Self>, id: QString) -> bool {
        let result = id
            .to_string()
            .parse::<i64>()
            .map_err(|_| Error::InvalidSelection)
            .and_then(|id| {
                paths::database_path().and_then(|path| NotesSession::open_note(&path, id))
            });
        match result {
            Ok(session) => {
                match session.window_state() {
                    Ok(state) => self.as_mut().rust_mut().window_state = state,
                    Err(error) => {
                        eprintln!("BetterNotes: window state: {error}");
                        self.as_mut().rust_mut().window_error = QString::from(&error.to_string());
                    }
                }
                self.as_mut().rust_mut().session = Some(session);
                self.as_mut().rust_mut().ready = true;
                self.finish(Ok(()), true)
            }
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn reload_note(self: Pin<&mut Self>) -> bool {
        self.perform(true, NotesSession::reload_note)
    }

    // Geometry failures are separate from content save failures, so autosave
    // cannot clear a window-state error before the user has seen it.
    #[allow(clippy::too_many_arguments)]
    pub fn save_window(
        mut self: Pin<&mut Self>,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
        screen: QString,
        collapsed: bool,
        positioned: bool,
        open: bool,
    ) -> bool {
        let state = WindowState {
            position: positioned.then_some((x, y)),
            width,
            height,
            screen: screen.to_string(),
            collapsed,
            open,
        };
        let result = self
            .session
            .as_ref()
            .ok_or(Error::NoSelection)
            .and_then(|session| session.save_window_state(&state));
        let success = result.is_ok();
        let message = result
            .err()
            .map(|error| error.to_string())
            .unwrap_or_default();
        if !success {
            eprintln!("BetterNotes: window state: {message}");
        }
        self.as_mut().rust_mut().window_error = QString::from(&message);
        if success {
            self.as_mut().rust_mut().window_state = state;
        }
        self.status_changed();
        success
    }

    pub fn saved_x(&self) -> i32 {
        self.window_state.position.map(|p| p.0).unwrap_or(0)
    }
    pub fn saved_y(&self) -> i32 {
        self.window_state.position.map(|p| p.1).unwrap_or(0)
    }
    pub fn saved_width(&self) -> i32 {
        self.window_state.width
    }
    pub fn saved_height(&self) -> i32 {
        self.window_state.height
    }
    pub fn saved_screen(&self) -> QString {
        QString::from(&self.window_state.screen)
    }
    pub fn saved_collapsed(&self) -> bool {
        self.window_state.collapsed
    }
    pub fn saved_positioned(&self) -> bool {
        self.window_state.position.is_some()
    }

    fn perform(
        mut self: Pin<&mut Self>,
        editor: bool,
        action: impl FnOnce(&mut NotesSession) -> Result<()>,
    ) -> bool {
        let result = match self.as_mut().rust_mut().session.as_mut() {
            Some(session) => action(session),
            None => Err(Error::NoSelection),
        };
        self.finish(result, editor)
    }

    fn finish(mut self: Pin<&mut Self>, result: Result<()>, editor: bool) -> bool {
        let success = result.is_ok();
        let message = result
            .err()
            .map(|error| error.to_string())
            .unwrap_or_default();
        if !success {
            eprintln!("BetterNotes: {message}");
        }
        {
            let mut state = self.as_mut().rust_mut();
            state.error_message = QString::from(&message);
            if let Some(session) = &state.session {
                let titles = session
                    .summaries()
                    .iter()
                    .map(|note| QString::from(&note.title))
                    .collect();
                let note_ids = session
                    .summaries()
                    .iter()
                    .map(|note| QString::from(&note.id.to_string()))
                    .collect();
                let current_id = session
                    .current()
                    .map(|note| QString::from(&note.id.to_string()))
                    .unwrap_or_default();
                let index = session
                    .current_index()
                    .and_then(|i| i32::try_from(i).ok())
                    .unwrap_or(-1);
                let title = session
                    .current()
                    .map(|note| QString::from(&note.title))
                    .unwrap_or_default();
                let content = session
                    .current()
                    .map(|note| QString::from(&note.content))
                    .unwrap_or_default();
                let snippets = session
                    .summaries()
                    .iter()
                    .map(|note| QString::from(&note.snippet))
                    .collect();
                let pinned_states = session
                    .summaries()
                    .iter()
                    .map(|note| QString::from(if note.is_pinned { "true" } else { "false" }))
                    .collect();
                let archived_states = session
                    .summaries()
                    .iter()
                    .map(|note| QString::from(if note.is_archived { "true" } else { "false" }))
                    .collect();
                let priorities = session
                    .summaries()
                    .iter()
                    .map(|note| QString::from(&note.priority.to_string()))
                    .collect();
                // One comma-joined entry per row, so a list delegate can show a
                // note's tags without a query of its own.
                let note_tags = session
                    .summaries()
                    .iter()
                    .map(|note| QString::from(&note.tags.join(",")))
                    .collect();
                let note_colors = session
                    .summary_colors()
                    .unwrap_or_default()
                    .iter()
                    .map(QString::from)
                    .collect();
                let note_reminders = session
                    .summary_reminders()
                    .unwrap_or_default()
                    .iter()
                    .map(|reminder| match reminder {
                        Some((at, recurrence)) => {
                            QString::from(&format!("{at}|{}", recurrence.as_str()))
                        }
                        None => QString::default(),
                    })
                    .collect();
                let trash = session.trash().unwrap_or_default();
                let trash_ids = trash
                    .iter()
                    .map(|(note, _)| QString::from(&note.id.to_string()))
                    .collect();
                let trash_titles = trash
                    .iter()
                    .map(|(note, _)| QString::from(&note.title))
                    .collect();
                let trash_snippets = trash
                    .iter()
                    .map(|(note, _)| QString::from(&note.snippet))
                    .collect();
                let trash_deleted_at = trash
                    .iter()
                    .map(|(_, at)| QString::from(&at.to_string()))
                    .collect();
                let all_tags = session
                    .list_tags()
                    .unwrap_or_default()
                    .iter()
                    .map(QString::from)
                    .collect();
                let is_pinned = session.current().map(|n| n.is_pinned).unwrap_or(false);
                let is_archived = session.current().map(|n| n.is_archived).unwrap_or(false);
                let priority = session.current().map(|n| n.priority).unwrap_or(0);
                let tags = session
                    .current()
                    .map(|n| n.tags.iter().map(QString::from).collect())
                    .unwrap_or_default();
                let tags_text = session
                    .current()
                    .map(|n| QString::from(&n.tags.join(", ")))
                    .unwrap_or_default();
                let dirty = session.dirty();
                let theme = session.theme().unwrap_or_default();
                let autostart_enabled = session.is_autostart_enabled().unwrap_or(false);
                let notes_stay_below = session.notes_stay_below().unwrap_or(true);
                let accent_color = session
                    .store()
                    .accent_color()
                    .unwrap_or_else(|_| betternotes_core::settings::DEFAULT_ACCENT.to_string());
                let locked_states = session
                    .summaries()
                    .iter()
                    .map(|note| QString::from(if note.is_locked { "true" } else { "false" }))
                    .collect();
                let is_locked = session.current().is_some_and(|note| note.is_locked);
                let vault_set = betternotes_core::vault::is_set(session.store()).unwrap_or(false);
                let vault_unlocked = betternotes_core::vault::is_unlocked();
                let shortcuts_json = betternotes_core::keymap::load(session.store())
                    .ok()
                    .and_then(|keys| serde_json::to_string(&keys).ok())
                    .unwrap_or_default();
                state.titles = titles;
                state.note_ids = note_ids;
                state.snippets = snippets;
                state.pinned_states = pinned_states;
                state.archived_states = archived_states;
                state.priorities = priorities;
                state.note_tags = note_tags;
                state.note_colors = note_colors;
                state.note_reminders = note_reminders;
                state.trash_ids = trash_ids;
                state.trash_titles = trash_titles;
                state.trash_snippets = trash_snippets;
                state.trash_deleted_at = trash_deleted_at;
                state.all_tags = all_tags;
                state.current_id = current_id;
                state.current_index = index;
                state.draft_title = title;
                state.draft_content = content;
                state.is_pinned = is_pinned;
                state.is_archived = is_archived;
                state.priority = priority;
                state.tags = tags;
                state.tags_text = tags_text;
                state.dirty = dirty;
                state.theme_mode = QString::from(theme.as_str());
                state.autostart_enabled = autostart_enabled;
                state.notes_stay_below = notes_stay_below;
                state.accent_color = QString::from(&accent_color);
                state.locked_states = locked_states;
                state.is_locked = is_locked;
                state.vault_set = vault_set;
                state.vault_unlocked = vault_unlocked;
                state.shortcuts_json = QString::from(&shortcuts_json);
            }
        }
        self.as_mut().list_changed();
        if editor && success {
            self.as_mut().selection_changed();
        }
        self.as_mut().theme_changed();
        self.as_mut().autostart_changed();
        self.as_mut().layer_changed();
        self.status_changed();
        success
    }

    pub fn create_note(self: Pin<&mut Self>) -> bool {
        self.perform(true, NotesSession::create)
    }
    pub fn select_note(self: Pin<&mut Self>, index: i32) -> bool {
        self.perform(true, |session| {
            session.select(usize::try_from(index).map_err(|_| Error::InvalidSelection)?)
        })
    }
    /// Moves the note to the trash; it can be restored for 30 days.
    pub fn delete_note(self: Pin<&mut Self>) -> bool {
        self.perform(true, NotesSession::trash_current)
    }
    pub fn reload(self: Pin<&mut Self>) -> bool {
        self.perform(true, NotesSession::reload)
    }
    pub fn save(self: Pin<&mut Self>) -> bool {
        // An initialization error has no draft to lose and must not trap the window.
        if !self.ready {
            return true;
        }
        self.perform(false, NotesSession::save)
    }

    pub fn edit_title(mut self: Pin<&mut Self>, title: QString) {
        {
            let mut state = self.as_mut().rust_mut();
            if let Some(session) = &mut state.session {
                session.edit_title(title.to_string());
                state.dirty = session.dirty();
                state.draft_title = title;
            }
        }
        self.status_changed();
    }

    pub fn edit_content(mut self: Pin<&mut Self>, content: QString) {
        {
            let mut state = self.as_mut().rust_mut();
            if let Some(session) = &mut state.session {
                session.edit_content(content.to_string());
                state.dirty = session.dirty();
                state.draft_content = content;
            }
        }
        self.status_changed();
    }

    pub fn set_theme_mode(mut self: Pin<&mut Self>, mode: QString) -> bool {
        let pref: ThemePreference = mode.to_string().parse().unwrap_or_default();
        let result = self
            .as_mut()
            .rust_mut()
            .session
            .as_mut()
            .ok_or(Error::NoSelection)
            .and_then(|session| session.set_theme(pref));
        if result.is_ok() {
            self.as_mut().rust_mut().theme_mode = mode;
            self.as_mut().theme_changed();
            true
        } else {
            false
        }
    }

    pub fn set_notes_stay_below(mut self: Pin<&mut Self>, enabled: bool) -> bool {
        let result = self
            .as_mut()
            .rust_mut()
            .session
            .as_mut()
            .ok_or(Error::NoSelection)
            .and_then(|session| session.set_notes_stay_below(enabled));
        if result.is_ok() {
            self.as_mut().rust_mut().notes_stay_below = enabled;
            self.as_mut().layer_changed();
            true
        } else {
            false
        }
    }

    pub fn set_note_pinned(self: Pin<&mut Self>, id: QString, pinned: bool) -> bool {
        match parse_note_id(&id) {
            Ok(id) => self.perform(false, |session| session.set_note_pinned(id, pinned)),
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn set_note_archived(self: Pin<&mut Self>, id: QString, archived: bool) -> bool {
        match parse_note_id(&id) {
            Ok(id) => self.perform(false, |session| session.set_note_archived(id, archived)),
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn delete_note_by_id(self: Pin<&mut Self>, id: QString) -> bool {
        match parse_note_id(&id) {
            Ok(id) => self.perform(false, |session| session.trash_note(id)),
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn restore_note(self: Pin<&mut Self>, id: QString) -> bool {
        match parse_note_id(&id) {
            Ok(id) => self.perform(false, |session| session.restore_note(id)),
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn delete_forever(self: Pin<&mut Self>, id: QString) -> bool {
        match parse_note_id(&id) {
            Ok(id) => self.perform(false, |session| session.delete_forever(id)),
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn empty_trash(self: Pin<&mut Self>) -> i32 {
        let mut count = 0;
        let success = self.perform(false, |session| {
            count = session.empty_trash(None)?;
            Ok(())
        });
        if success {
            i32::try_from(count).unwrap_or(i32::MAX)
        } else {
            -1
        }
    }

    pub fn add_note_tag(self: Pin<&mut Self>, id: QString, tag: QString) -> bool {
        match parse_note_id(&id) {
            Ok(id) => self.perform(false, |session| session.add_note_tag(id, &tag.to_string())),
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn note_plain_text(&self, id: QString) -> QString {
        let text = parse_note_id(&id).and_then(|id| {
            self.session
                .as_ref()
                .ok_or(Error::NoSelection)?
                .plain_text(id)
        });
        QString::from(&text.unwrap_or_default())
    }

    pub fn search(mut self: Pin<&mut Self>, query: QString) {
        let q_str = query.to_string();
        let (ids, titles, snippets) = if let Some(session) = &self.session {
            if q_str.trim().is_empty() {
                (
                    QStringList::default(),
                    QStringList::default(),
                    QStringList::default(),
                )
            } else {
                match session.search(&q_str) {
                    Ok(results) => {
                        let ids = results
                            .iter()
                            .map(|r| QString::from(&r.id.to_string()))
                            .collect();
                        let titles = results.iter().map(|r| QString::from(&r.title)).collect();
                        let snippets = results.iter().map(|r| QString::from(&r.snippet)).collect();
                        (ids, titles, snippets)
                    }
                    Err(err) => {
                        eprintln!("BetterNotes: search error: {err}");
                        (
                            QStringList::default(),
                            QStringList::default(),
                            QStringList::default(),
                        )
                    }
                }
            }
        } else {
            (
                QStringList::default(),
                QStringList::default(),
                QStringList::default(),
            )
        };
        {
            let mut state = self.as_mut().rust_mut();
            state.search_result_ids = ids;
            state.search_result_titles = titles;
            state.search_result_snippets = snippets;
        }
        self.as_mut().search_changed();
    }

    pub fn set_pinned(self: Pin<&mut Self>, pinned: bool) -> bool {
        self.perform(true, |session| session.set_pinned(pinned))
    }

    pub fn set_archived(self: Pin<&mut Self>, archived: bool) -> bool {
        self.perform(true, |session| session.set_archived(archived))
    }

    pub fn set_priority(self: Pin<&mut Self>, priority: i32) -> bool {
        self.perform(true, |session| session.set_priority(priority))
    }

    pub fn set_tags(self: Pin<&mut Self>, tags: QString) -> bool {
        let rust_tags: Vec<String> = tags
            .to_string()
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        self.perform(true, |session| session.set_tags(rust_tags))
    }

    pub fn note_color(&self) -> QString {
        let color = self
            .session
            .as_ref()
            .map(|s| s.note_color())
            .unwrap_or_else(|| "yellow".to_string());
        QString::from(&color)
    }

    pub fn set_note_color(mut self: Pin<&mut Self>, color: QString) -> bool {
        let color_str = color.to_string();
        let result = self
            .as_mut()
            .rust_mut()
            .session
            .as_mut()
            .ok_or(Error::NoSelection)
            .and_then(|session| session.set_note_color(&color_str));
        result.is_ok()
    }

    pub fn note_font_family(&self) -> QString {
        let family = self
            .session
            .as_ref()
            .map(|s| s.note_font_family())
            .unwrap_or_else(|| "default".to_string());
        QString::from(&family)
    }

    pub fn set_note_font_family(mut self: Pin<&mut Self>, family: QString) -> bool {
        let family_str = family.to_string();
        let result = self
            .as_mut()
            .rust_mut()
            .session
            .as_mut()
            .ok_or(Error::NoSelection)
            .and_then(|session| session.set_note_font_family(&family_str));
        result.is_ok()
    }

    pub fn note_font_size(&self) -> i32 {
        self.session
            .as_ref()
            .map(|s| s.note_font_size())
            .unwrap_or(13)
    }

    pub fn set_note_font_size(mut self: Pin<&mut Self>, size: i32) -> bool {
        let result = self
            .as_mut()
            .rust_mut()
            .session
            .as_mut()
            .ok_or(Error::NoSelection)
            .and_then(|session| session.set_note_font_size(size));
        result.is_ok()
    }

    pub fn save_image_as(
        mut self: Pin<&mut Self>,
        image_url: QString,
        target_url: QString,
    ) -> bool {
        let local = |url: &QString| QUrl::from(url).to_local_file().map(|path| path.to_string());
        let result = match (local(&image_url), local(&target_url)) {
            (Some(source), Some(target)) => betternotes_core::save_copy(
                std::path::Path::new(&source),
                std::path::Path::new(&target),
            ),
            _ => Err(Error::Io(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "Only local files can be saved",
            ))),
        };
        let message = match &result {
            Ok(()) => String::new(),
            Err(error) => format!("Could not save the image: {error}"),
        };
        if !message.is_empty() {
            eprintln!("BetterNotes: {message}");
        }
        self.as_mut().rust_mut().error_message = QString::from(&message);
        self.as_mut().status_changed();
        result.is_ok()
    }

    pub fn image_file_name(&self, image_url: QString) -> QString {
        let name = QUrl::from(&image_url).file_name().to_string();
        QString::from(betternotes_core::original_filename(&name))
    }

    pub fn pictures_folder(&self) -> QString {
        ffi::platformPicturesFolder()
    }

    pub fn documents_folder(&self) -> QString {
        ffi::platformDocumentsFolder()
    }

    fn note_attachments(&self) -> Vec<(betternotes_core::Attachment, std::path::PathBuf)> {
        let Some(session) = self.session.as_ref() else {
            return Vec::new();
        };
        let (Some(note), Ok(data_dir)) = (
            session.current(),
            paths::data_directory(
                std::env::var_os("XDG_DATA_HOME").as_deref(),
                std::env::var_os("HOME").as_deref(),
            ),
        ) else {
            return Vec::new();
        };
        session
            .list_attachments(note.id)
            .unwrap_or_default()
            .into_iter()
            .filter(|attachment| !attachment.mime_type.starts_with("image/"))
            .map(|attachment| {
                let path = betternotes_core::stored_path(&data_dir, &attachment);
                (attachment, path)
            })
            .collect()
    }

    pub fn attachments_json(&self) -> QString {
        let list: Vec<serde_json::Value> = self
            .note_attachments()
            .iter()
            .map(|(attachment, path)| {
                serde_json::json!({
                    "id": attachment.id,
                    "name": attachment.filename,
                    "size": attachment.byte_size,
                    "url": QUrl::from_local_file(&QString::from(path.to_string_lossy().as_ref()))
                        .to_qstring()
                        .to_string(),
                    "openable": betternotes_core::can_open(&attachment.filename),
                })
            })
            .collect();
        QString::from(&serde_json::Value::Array(list).to_string())
    }

    pub fn attach_file(mut self: Pin<&mut Self>, file_url: QString) -> bool {
        let path = local_path(&file_url);
        let result = match self.as_mut().rust_mut().session.as_mut() {
            Some(session) => session
                .add_attachment_file(std::path::Path::new(&path))
                .map(|_| ()),
            None => Err(Error::NoSelection),
        };
        let message = match &result {
            Ok(()) => String::new(),
            Err(error) => format!("Could not attach the file: {error}"),
        };
        self.as_mut().rust_mut().error_message = QString::from(&message);
        self.as_mut().status_changed();
        result.is_ok()
    }

    pub fn remove_attachment(mut self: Pin<&mut Self>, id: QString) -> bool {
        let id = id.to_string();
        // Only an attachment of this note may be removed from it.
        if !self.note_attachments().iter().any(|(a, _)| a.id == id) {
            return false;
        }
        let Ok(data_dir) = paths::data_directory(
            std::env::var_os("XDG_DATA_HOME").as_deref(),
            std::env::var_os("HOME").as_deref(),
        ) else {
            return false;
        };
        match self.as_mut().rust_mut().session.as_mut() {
            Some(session) => session.delete_attachment(&data_dir, &id).is_ok(),
            None => false,
        }
    }

    pub fn attachment_open_url(&self, id: QString) -> QString {
        let id = id.to_string();
        self.note_attachments()
            .into_iter()
            .find(|(attachment, _)| {
                attachment.id == id && betternotes_core::can_open(&attachment.filename)
            })
            .map(|(_, path)| {
                QUrl::from_local_file(&QString::from(path.to_string_lossy().as_ref())).to_qstring()
            })
            .unwrap_or_default()
    }

    pub fn paste_clipboard_image(self: Pin<&mut Self>) -> QString {
        let path = ffi::platformClipboardImageToFile().to_string();
        if path.is_empty() {
            return QString::default();
        }
        let url = QUrl::from_local_file(&QString::from(&path)).to_qstring();
        let stored = self.attach_image(url);
        // The attachment is a copy; the temporary file is ours to remove.
        let _ = std::fs::remove_file(&path);
        stored
    }

    pub fn clipboard_file_urls(&self) -> QString {
        ffi::platformClipboardImageUrls()
    }

    pub fn attach_image(mut self: Pin<&mut Self>, file_url: QString) -> QString {
        // Dropped and chosen files arrive as percent-encoded file URLs.
        let url = QUrl::from(&file_url);
        let path = match url.to_local_file() {
            Some(path) => path.to_string(),
            None => file_url.to_string(),
        };
        let result = match self.as_mut().rust_mut().session.as_mut() {
            Some(session) => session
                .add_attachment_file(std::path::Path::new(&path))
                .and_then(|attachment| {
                    let data_dir = betternotes_core::paths::data_directory(
                        std::env::var_os("XDG_DATA_HOME").as_deref(),
                        std::env::var_os("HOME").as_deref(),
                    )?;
                    Ok(data_dir
                        .join("attachments")
                        .join(&attachment.stored_rel_path))
                }),
            None => Err(Error::NoSelection),
        };
        match result {
            Ok(stored) => QUrl::from_local_file(&QString::from(stored.to_string_lossy().as_ref()))
                .to_qstring(),
            Err(error) => {
                eprintln!("BetterNotes: could not attach image: {error}");
                self.as_mut().rust_mut().error_message =
                    QString::from(&format!("Could not add the image: {error}"));
                self.as_mut().status_changed();
                QString::default()
            }
        }
    }

    pub fn set_autostart(mut self: Pin<&mut Self>, enabled: bool) -> bool {
        let result = betternotes_core::set_autostart(enabled, None);
        let success = result.is_ok();
        if success {
            self.as_mut().rust_mut().autostart_enabled = enabled;
            self.as_mut().autostart_changed();
        }
        success
    }

    pub fn copy_to_clipboard(self: Pin<&mut Self>, text: QString) -> bool {
        ffi::platformCopyToClipboard(&text);
        true
    }

    pub fn get_clipboard_text(&self) -> QString {
        ffi::platformGetClipboardText()
    }

    pub fn cursor_global_x(&self) -> i32 {
        ffi::platformCursorGlobalX()
    }

    pub fn cursor_global_y(&self) -> i32 {
        ffi::platformCursorGlobalY()
    }

    pub fn send_notification(self: Pin<&mut Self>, title: QString, body: QString) -> bool {
        let _ =
            betternotes_core::NotificationService::notify(&title.to_string(), &body.to_string());
        true
    }

    pub fn set_reminder(self: Pin<&mut Self>, timestamp_sec: i64, recurrence: QString) -> bool {
        let rec = betternotes_core::Recurrence::parse(&recurrence.to_string());
        self.perform(false, |session| {
            if let Some(note) = session.current() {
                session.set_reminder(note.id, timestamp_sec, rec)?;
            }
            Ok(())
        })
    }

    pub fn clear_reminder(self: Pin<&mut Self>) -> bool {
        self.perform(false, |session| {
            if let Some(note) = session.current() {
                session.clear_reminder(note.id)?;
            }
            Ok(())
        })
    }

    pub fn check_reminders(mut self: Pin<&mut Self>) -> i32 {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        let mut triggered = 0;
        let texts = self.reminder_texts.clone();
        if let Some(session) = self.as_mut().rust_mut().session.as_mut() {
            if let Ok(due_list) = session.check_due_reminders(now) {
                for due in due_list {
                    let title = match due.note_title.trim() {
                        "" => "Untitled note".to_string(),
                        title => title.to_string(),
                    };
                    let [body, open, snooze] = texts.clone();
                    let note_id = due.note_id;
                    // A recurring reminder keeps its schedule; with one reminder
                    // per note, snoozing would replace it.
                    let can_snooze = due.recurrence == betternotes_core::Recurrence::None;
                    // The notification waits for a button or for being closed,
                    // so it runs off the GUI thread and reports back through
                    // the action queue the GUI already polls.
                    std::thread::spawn(move || {
                        let mut actions = vec![("open", open.as_str())];
                        if can_snooze {
                            actions.push(("snooze", snooze.as_str()));
                        }
                        let chosen = betternotes_core::NotificationService::notify_with_actions(
                            &title, &body, &actions,
                        );
                        let action = match chosen.ok().flatten().as_deref() {
                            Some("open") => betternotes_core::IpcAction::OpenNote(note_id),
                            Some("snooze") => betternotes_core::IpcAction::SnoozeReminder(note_id),
                            _ => return,
                        };
                        if let Ok(mut queue) = betternotes_core::global_ipc_queue().lock() {
                            queue.push_back(action);
                        }
                    });
                    let _ = session.dismiss_reminder(due.reminder_id, now);
                    triggered += 1;
                }
            }
        }
        // A fired one-time reminder is gone and a recurring one moved on.
        if triggered > 0 {
            self.finish(Ok(()), false);
        }
        triggered
    }

    pub fn open_files(mut self: Pin<&mut Self>, paths: QStringList) -> QStringList {
        let paths: Vec<String> = paths.iter().map(|path| path.to_string()).collect();
        let opened = self.as_mut().open_file_paths(&paths);
        opened
            .iter()
            .map(|id| QString::from(&id.to_string()))
            .collect()
    }

    fn open_file_paths(mut self: Pin<&mut Self>, paths: &[String]) -> Vec<i64> {
        let mut ids = Vec::new();
        let mut failures = Vec::new();
        let result = paths::data_directory(
            std::env::var_os("XDG_DATA_HOME").as_deref(),
            std::env::var_os("HOME").as_deref(),
        );
        if let (Some(session), Ok(data_dir)) = (self.as_mut().rust_mut().session.as_mut(), result) {
            for path in paths.iter().take(betternotes_core::open_files::MAX_FILES) {
                match betternotes_core::open_files::note_from_file(
                    session.store(),
                    &data_dir,
                    std::path::Path::new(path),
                ) {
                    Ok(id) => ids.push(id),
                    Err(error) => failures.push(format!(
                        "{}: {error}",
                        std::path::Path::new(path)
                            .file_name()
                            .map(|name| name.to_string_lossy().into_owned())
                            .unwrap_or_else(|| path.clone())
                    )),
                }
            }
        }
        let result = if failures.is_empty() {
            Ok(())
        } else {
            Err(Error::Ipc(format!(
                "Could not open {}: {}",
                failures.len(),
                failures.join("; ")
            )))
        };
        self.as_mut().perform(false, |session| {
            session.reload()?;
            result
        });
        ids
    }

    pub fn auto_backup_settings(&self) -> QString {
        let (Some(session), Ok(data_dir)) = (self.session.as_ref(), data_directory()) else {
            return QString::default();
        };
        let Ok(settings) = betternotes_core::auto_backup::AutoBackupSettings::load(session.store())
        else {
            return QString::default();
        };
        QString::from(
            &serde_json::json!({
                "enabled": settings.enabled,
                "interval": settings.interval,
                "keep": settings.keep,
                "folder": settings.folder,
                "target": settings.target(&data_dir).to_string_lossy(),
                "last": settings.last,
            })
            .to_string(),
        )
    }

    pub fn set_auto_backup_settings(
        self: Pin<&mut Self>,
        enabled: bool,
        interval: QString,
        keep: i32,
        folder: QString,
    ) -> bool {
        let folder = if folder.is_empty() {
            String::new()
        } else {
            local_path(&folder)
        };
        self.perform(false, |session| {
            let current = betternotes_core::auto_backup::AutoBackupSettings::load(session.store())?;
            betternotes_core::auto_backup::AutoBackupSettings {
                enabled,
                interval: interval.to_string(),
                keep: u32::try_from(keep).unwrap_or(1),
                folder,
                ..current
            }
            .save(session.store())
        })
    }

    pub fn backup_now(mut self: Pin<&mut Self>) -> QString {
        let mut made = String::new();
        self.as_mut().perform(false, |session| {
            let path =
                betternotes_core::auto_backup::backup_now(session.store(), &data_directory()?)?;
            made = path.to_string_lossy().into_owned();
            Ok(())
        });
        QString::from(&made)
    }

    pub fn run_auto_backup(&self) {
        // Its own connection: a backup copies every attachment and must not
        // hold up the window.
        std::thread::spawn(|| {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|elapsed| elapsed.as_secs() as i64)
                .unwrap_or(0);
            let result = paths::database_path().and_then(|path| {
                let store = betternotes_core::NoteStore::open(&path)?;
                betternotes_core::auto_backup::run_if_due(&store, &data_directory()?, now)
            });
            match result {
                Ok(Some(path)) => eprintln!("BetterNotes: backed up to {}", path.display()),
                Ok(None) => {}
                Err(error) => eprintln!("BetterNotes: automatic backup failed: {error}"),
            }
        });
    }

    pub fn set_up_password(mut self: Pin<&mut Self>, password: QString) -> QString {
        let mut refused = String::new();
        self.as_mut().perform(false, |session| {
            if let Err(error) =
                betternotes_core::vault::set_up(session.store(), &password.to_string())
            {
                refused = error.to_string();
            }
            Ok(())
        });
        QString::from(&refused)
    }

    pub fn unlock_notes(mut self: Pin<&mut Self>, password: QString) -> bool {
        let mut unlocked = false;
        self.as_mut().perform(false, |session| {
            unlocked = betternotes_core::vault::unlock(session.store(), &password.to_string())?;
            Ok(())
        });
        unlocked
    }

    pub fn lock_notes(self: Pin<&mut Self>) {
        betternotes_core::vault::lock();
        self.finish(Ok(()), false);
    }

    pub fn change_password(
        mut self: Pin<&mut Self>,
        current: QString,
        replacement: QString,
    ) -> QString {
        let mut refused = String::new();
        self.as_mut().perform(false, |session| {
            if let Err(error) = betternotes_core::vault::change_password(
                session.store(),
                &current.to_string(),
                &replacement.to_string(),
            ) {
                refused = error.to_string();
            }
            Ok(())
        });
        QString::from(&refused)
    }

    pub fn set_locked(self: Pin<&mut Self>, locked: bool) -> bool {
        self.perform(true, |session| session.set_locked(locked))
    }

    pub fn set_note_locked(self: Pin<&mut Self>, id: QString, locked: bool) -> bool {
        match parse_note_id(&id) {
            Ok(id) => self.perform(false, |session| session.set_note_locked(id, locked)),
            Err(error) => self.finish(Err(error), false),
        }
    }

    pub fn refresh_state(self: Pin<&mut Self>) {
        self.finish(Ok(()), false);
    }

    pub fn set_accent_color(self: Pin<&mut Self>, color: QString) -> bool {
        self.perform(false, |session| {
            session.store().set_accent_color(&color.to_string())
        })
    }

    pub fn set_shortcut(mut self: Pin<&mut Self>, action: QString, sequence: QString) -> QString {
        let mut refused = String::new();
        self.as_mut().perform(false, |session| {
            if let Err(error) = betternotes_core::keymap::set(
                session.store(),
                &action.to_string(),
                &sequence.to_string(),
            ) {
                refused = error.to_string();
            }
            Ok(())
        });
        QString::from(&refused)
    }

    pub fn reset_shortcuts(self: Pin<&mut Self>) -> bool {
        self.perform(false, |session| {
            betternotes_core::keymap::reset(session.store())
        })
    }

    pub fn recent_searches(&self) -> QStringList {
        self.session
            .as_ref()
            .and_then(|session| session.store().recent_searches().ok())
            .unwrap_or_default()
            .iter()
            .map(QString::from)
            .collect()
    }

    pub fn remember_search(self: Pin<&mut Self>, query: QString) {
        if let Some(session) = self.session.as_ref() {
            if let Err(error) = session.store().remember_search(&query.to_string()) {
                eprintln!("BetterNotes: could not remember the search: {error}");
            }
        }
    }

    pub fn clear_recent_searches(self: Pin<&mut Self>) {
        if let Some(session) = self.session.as_ref() {
            let _ = session.store().clear_recent_searches();
        }
    }

    pub fn set_reminder_texts(
        mut self: Pin<&mut Self>,
        body: QString,
        open_label: QString,
        snooze_label: QString,
    ) {
        self.as_mut().rust_mut().reminder_texts = [
            body.to_string(),
            open_label.to_string(),
            snooze_label.to_string(),
        ];
    }

    pub fn note_reminder(&self, id: QString) -> QString {
        let Some((session, id)) = self.session.as_ref().zip(id.to_string().parse().ok()) else {
            return QString::default();
        };
        match session.get_reminder(id) {
            Ok(Some(reminder)) => QString::from(&format!(
                "{}|{}",
                reminder.remind_at,
                reminder.recurrence.as_str()
            )),
            _ => QString::default(),
        }
    }

    pub fn set_note_reminder(
        self: Pin<&mut Self>,
        id: QString,
        timestamp_sec: i64,
        recurrence: QString,
    ) -> bool {
        let recurrence = betternotes_core::Recurrence::parse(&recurrence.to_string());
        self.perform(false, |session| {
            let id = id
                .to_string()
                .parse()
                .map_err(|_| Error::InvalidSelection)?;
            session.set_reminder(id, timestamp_sec, recurrence)?;
            Ok(())
        })
    }

    pub fn clear_note_reminder(self: Pin<&mut Self>, id: QString) -> bool {
        self.perform(false, |session| {
            let id = id
                .to_string()
                .parse()
                .map_err(|_| Error::InvalidSelection)?;
            session.clear_reminder(id)
        })
    }

    pub fn export_notes_json(self: Pin<&mut Self>, file_path: QString) -> bool {
        self.perform(false, |session| {
            session.export_json(std::path::Path::new(&local_path(&file_path)))
        })
    }

    pub fn export_notes_markdown(self: Pin<&mut Self>, dir_path: QString) -> bool {
        self.perform(false, |session| {
            session.export_markdown(std::path::Path::new(&local_path(&dir_path)))
        })
    }

    pub fn import_notes_json(mut self: Pin<&mut Self>, file_path: QString) -> i32 {
        let path = local_path(&file_path);
        let mut count = 0;
        let success = self.as_mut().perform(true, |session| {
            count = session.import_json(std::path::Path::new(&path))? as i32;
            Ok(())
        });
        if success {
            count
        } else {
            -1
        }
    }

    pub fn import_note_markdown(mut self: Pin<&mut Self>, file_path: QString) -> i32 {
        let path = local_path(&file_path);
        let mut count = 0;
        let success = self.as_mut().perform(true, |session| {
            count = session.import_markdown(std::path::Path::new(&path))? as i32;
            Ok(())
        });
        if success {
            count
        } else {
            -1
        }
    }

    pub fn poll_ipc_action(mut self: Pin<&mut Self>) -> QString {
        let action = betternotes_core::global_ipc_queue()
            .lock()
            .unwrap()
            .pop_front();
        match action {
            Some(betternotes_core::IpcAction::Activate) => QString::from("activate"),
            Some(betternotes_core::IpcAction::QuickCapture) => QString::from("quick_capture"),
            Some(betternotes_core::IpcAction::OpenNote(id)) => {
                self.as_mut().reload();
                QString::from(&format!("open:{id}"))
            }
            Some(betternotes_core::IpcAction::Reload) => {
                self.as_mut().reload();
                QString::from("reload")
            }
            Some(betternotes_core::IpcAction::OpenFiles(paths)) => {
                let ids = self.as_mut().open_file_paths(&paths);
                QString::from(&format!(
                    "opened:{}",
                    ids.iter().map(i64::to_string).collect::<Vec<_>>().join(",")
                ))
            }
            Some(betternotes_core::IpcAction::SnoozeReminder(id)) => {
                let at = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|elapsed| elapsed.as_secs() as i64 + 600)
                    .unwrap_or(0);
                let snoozed = self.as_mut().perform(false, |session| {
                    session.set_reminder(id, at, betternotes_core::Recurrence::None)?;
                    Ok(())
                });
                QString::from(&if snoozed {
                    format!("snoozed:{id}")
                } else {
                    String::new()
                })
            }
            None => QString::from(""),
        }
    }
}

/// Note ids reach QML as strings; anything that is not one is rejected.
fn parse_note_id(id: &QString) -> Result<i64> {
    id.to_string()
        .trim()
        .parse()
        .map_err(|_| Error::InvalidSelection)
}
