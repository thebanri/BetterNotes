//! Qt adapter for the independent Rust editing session. No SQL or note rules in QML.
use betternotes_core::{paths, Error, NotesSession, Result};
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
    }
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QStringList, titles, READ, NOTIFY = list_changed)]
        #[qproperty(i32, current_index, READ, NOTIFY = selection_changed, cxx_name = "currentIndex")]
        #[qproperty(QString, draft_title, READ, NOTIFY = selection_changed, cxx_name = "draftTitle")]
        #[qproperty(QString, draft_content, READ, NOTIFY = selection_changed, cxx_name = "draftContent")]
        #[qproperty(bool, ready, READ, NOTIFY = status_changed)]
        #[qproperty(bool, dirty, READ, NOTIFY = status_changed)]
        #[qproperty(QString, error_message, READ, NOTIFY = status_changed, cxx_name = "errorMessage")]
        type NotesBackend = super::NotesBackendRust;

        #[qsignal]
        fn list_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn selection_changed(self: Pin<&mut Self>);
        #[qsignal]
        fn status_changed(self: Pin<&mut Self>);

        #[qinvokable]
        fn initialize(self: Pin<&mut Self>) -> bool;
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
    }
}

pub struct NotesBackendRust {
    session: Option<NotesSession>,
    titles: QStringList,
    current_index: i32,
    draft_title: QString,
    draft_content: QString,
    ready: bool,
    dirty: bool,
    error_message: QString,
}

impl Default for NotesBackendRust {
    fn default() -> Self {
        Self {
            session: None,
            titles: QStringList::default(),
            current_index: -1,
            draft_title: QString::default(),
            draft_content: QString::default(),
            ready: false,
            dirty: false,
            error_message: QString::default(),
        }
    }
}

impl ffi::NotesBackend {
    pub fn initialize(mut self: Pin<&mut Self>) -> bool {
        if self.ready {
            return true;
        }
        let result = paths::database_path().and_then(|path| NotesSession::open(&path));
        match result {
            Ok(session) => {
                self.as_mut().rust_mut().session = Some(session);
                self.as_mut().rust_mut().ready = true;
                self.finish(Ok(()), true)
            }
            Err(error) => self.finish(Err(error), false),
        }
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
                let dirty = session.dirty();
                state.titles = titles;
                state.current_index = index;
                state.draft_title = title;
                state.draft_content = content;
                state.dirty = dirty;
            }
        }
        self.as_mut().list_changed();
        if editor && success {
            self.as_mut().selection_changed();
        }
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
}
