#![allow(clippy::too_many_arguments)]
//! Qt adapter for the independent Rust editing session. No SQL or note rules in QML.
use betternotes_core::{paths, Error, NotesSession, Result, ThemePreference, WindowState};
use cxx_qt::CxxQtType;
use cxx_qt_lib::{QString, QStringList};
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

        #[qinvokable]
        #[cxx_name = "pollIpcAction"]
        fn poll_ipc_action(self: Pin<&mut Self>) -> QString;
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
            let session = NotesSession::open(&path)?;
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
                state.titles = titles;
                state.note_ids = note_ids;
                state.snippets = snippets;
                state.pinned_states = pinned_states;
                state.archived_states = archived_states;
                state.priorities = priorities;
                state.note_tags = note_tags;
                state.note_colors = note_colors;
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
    pub fn delete_note(self: Pin<&mut Self>) -> bool {
        self.perform(true, NotesSession::delete_current)
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
            Ok(id) => self.perform(false, |session| session.delete_note(id)),
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

    pub fn attach_image(mut self: Pin<&mut Self>, file_url: QString) -> QString {
        let url_str = file_url.to_string();
        let path_str = if let Some(stripped) = url_str.strip_prefix("file://") {
            stripped
        } else {
            &url_str
        };
        let source_path = std::path::Path::new(path_str);
        if let Some(session) = self.as_mut().rust_mut().session.as_mut() {
            if let Ok(att) = session.add_attachment_file(source_path) {
                if let Ok(data_dir) = betternotes_core::paths::data_directory(
                    std::env::var_os("XDG_DATA_HOME").as_deref(),
                    std::env::var_os("HOME").as_deref(),
                ) {
                    let full_path = data_dir.join("attachments").join(&att.stored_rel_path);
                    return QString::from(&format!("file://{}", full_path.display()));
                }
            }
        }
        QString::default()
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
        let mut rust = self.as_mut().rust_mut();
        let session_opt = rust.session.as_mut();
        if let Some(session) = session_opt {
            if let Ok(due_list) = session.check_due_reminders(now) {
                for due in due_list {
                    let _ = betternotes_core::NotificationService::notify(
                        &format!("Reminder: {}", due.note_title),
                        "Your sticky note reminder is due now.",
                    );
                    let _ = session.dismiss_reminder(due.reminder_id);
                    triggered += 1;
                }
            }
        }
        triggered
    }

    pub fn export_notes_json(self: Pin<&mut Self>, file_path: QString) -> bool {
        self.perform(false, |session| {
            session.export_json(std::path::Path::new(&file_path.to_string()))
        })
    }

    pub fn export_notes_markdown(self: Pin<&mut Self>, dir_path: QString) -> bool {
        self.perform(false, |session| {
            session.export_markdown(std::path::Path::new(&dir_path.to_string()))
        })
    }

    pub fn import_notes_json(mut self: Pin<&mut Self>, file_path: QString) -> i32 {
        let path = file_path.to_string();
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
        let path = file_path.to_string();
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
