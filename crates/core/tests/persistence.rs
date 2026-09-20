use betternotes_core::{Error, NoteStore, NotesSession};
use rusqlite::Connection;

#[test]
fn crud_unicode_sql_text_and_reopen_preserve_data() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let store = NoteStore::open(&path).unwrap();
    assert!(store.list().unwrap().is_empty());
    let mut note = store.create().unwrap();
    note.title = "İstanbul 🦀 '); DROP TABLE notes; --".into();
    note.content = "<script>alert('text only')</script>\n日本語\0end".into();
    let saved = store.update(&note).unwrap();
    assert!(saved.updated_at >= saved.created_at);
    assert_eq!(saved.revision, 1);
    assert_eq!(store.list().unwrap()[0].title, saved.title);
    drop(store);
    let store = NoteStore::open(&path).unwrap();
    assert_eq!(store.get(saved.id).unwrap(), saved);
    store.delete(&saved).unwrap();
    let replacement = store.create().unwrap();
    assert_ne!(saved.id, replacement.id);
    drop(store);
    let store = NoteStore::open(&path).unwrap();
    assert!(matches!(store.get(saved.id), Err(Error::NotFound(_))));
    assert_eq!(store.list().unwrap().len(), 1);
}

#[test]
fn newer_unrelated_and_corrupt_databases_are_not_replaced() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("future.sqlite3");
    let connection = Connection::open(&path).unwrap();
    connection.execute_batch("CREATE TABLE precious(value TEXT); INSERT INTO precious VALUES ('keep'); PRAGMA user_version=99;").unwrap();
    assert!(matches!(
        NoteStore::open(&path),
        Err(Error::UnsupportedSchema(99))
    ));
    let value: String = connection
        .query_row("SELECT value FROM precious", [], |r| r.get(0))
        .unwrap();
    assert_eq!(value, "keep");
    connection.pragma_update(None, "user_version", 0).unwrap();
    assert!(matches!(
        NoteStore::open(&path),
        Err(Error::UnrecognizedDatabase)
    ));
    assert_eq!(
        connection
            .query_row("SELECT value FROM precious", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "keep"
    );
    let corrupt = directory.path().join("corrupt.sqlite3");
    std::fs::write(&corrupt, b"not a sqlite database").unwrap();
    assert!(NoteStore::open(&corrupt).is_err());
    assert_eq!(std::fs::read(corrupt).unwrap(), b"not a sqlite database");
}

#[test]
fn session_saves_before_switch_and_create_and_reopens_latest_note() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();
    session.create().unwrap();
    let first_id = session.current().unwrap().id;
    session.edit_title("First".into());
    session.edit_content("first body".into());
    assert!(session.dirty());
    session.create().unwrap();
    assert!(!session.dirty());
    session.edit_title("Second".into());
    session.select(1).unwrap();
    assert_eq!(session.current().unwrap().content, "first body");
    assert_eq!(session.current().unwrap().id, first_id);
    assert_eq!(session.summaries()[0].title, "Second");
    drop(session);
    let session = NotesSession::open(&path).unwrap();
    assert_eq!(session.current().unwrap().title, "Second");
}

#[test]
fn locked_writes_preserve_draft_and_selection_and_can_be_retried() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();
    session.create().unwrap();
    session.create().unwrap();
    let id = session.current().unwrap().id;
    session.edit_content("unsaved important text".into());
    let lock = Connection::open(&path).unwrap();
    lock.execute_batch("BEGIN IMMEDIATE").unwrap();
    assert!(session.save().is_err());
    assert!(session.select(1).is_err());
    assert!(session.create().is_err());
    assert!(session.delete_current().is_err());
    assert!(session.dirty());
    assert_eq!(session.current().unwrap().id, id);
    assert_eq!(session.current().unwrap().content, "unsaved important text");
    assert_eq!(session.summaries().len(), 2);
    lock.execute_batch("ROLLBACK").unwrap();
    session.save().unwrap();
    assert!(!session.dirty());
    assert_eq!(
        NoteStore::open(&path).unwrap().get(id).unwrap().content,
        "unsaved important text"
    );
}

#[test]
fn concurrent_edits_and_deletions_never_silently_overwrite() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();
    session.create().unwrap();
    let store = NoteStore::open(&path).unwrap();
    let mut other = store.get(session.current().unwrap().id).unwrap();
    other.title = "Other process".into();
    let saved = store.update(&other).unwrap();
    session.edit_title("My draft".into());
    assert!(matches!(session.save(), Err(Error::Conflict)));
    assert!(matches!(session.delete_current(), Err(Error::Conflict)));
    assert!(session.dirty());
    assert_eq!(session.current().unwrap().title, "My draft");
    assert_eq!(store.get(saved.id).unwrap().title, "Other process");
    session.reload().unwrap();
    assert!(!session.dirty());
    assert_eq!(session.current().unwrap().title, "Other process");
    store.delete(&saved).unwrap();
    session.edit_content("still here".into());
    assert!(matches!(session.save(), Err(Error::Conflict)));
    session.reload().unwrap();
    assert!(session.current().is_none());
    assert!(session.summaries().is_empty());
}

#[test]
fn confirmed_delete_discards_only_selected_draft() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();
    session.create().unwrap();
    session.edit_title("Keep".into());
    session.create().unwrap();
    session.edit_content("Discard".into());
    session.delete_current().unwrap();
    assert!(session.current().is_none());
    assert!(!session.dirty());
    assert_eq!(session.summaries()[0].title, "Keep");
    assert!(matches!(session.select(99), Err(Error::InvalidSelection)));
    assert!(matches!(session.delete_current(), Err(Error::NoSelection)));
}

#[test]
fn incomplete_schema_and_filesystem_errors_are_reported_without_recovery_writes() {
    let directory = tempfile::tempdir().unwrap();
    assert!(NoteStore::open(directory.path()).is_err());
    assert!(NoteStore::open(&directory.path().join("absent/notes.sqlite3")).is_err());
    let path = directory.path().join("notes.sqlite3");
    let store = NoteStore::open(&path).unwrap();
    let note = store.create().unwrap();
    drop(store);
    let connection = Connection::open(&path).unwrap();
    connection
        .execute_batch("ALTER TABLE notes RENAME COLUMN revision TO old_revision;")
        .unwrap();
    assert!(NoteStore::open(&path).is_err());
    assert_eq!(
        connection
            .query_row("SELECT id FROM notes", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        note.id
    );
}

#[test]
fn abrupt_exit_recovers_committed_wal_and_discards_uncommitted_transaction() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let status = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", "abrupt_exit_writer"])
        .env("BETTERNOTES_CRASH_TEST_PATH", &path)
        .status()
        .unwrap();
    assert!(status.success());
    let store = NoteStore::open(&path).unwrap();
    let notes = store.list().unwrap();
    assert_eq!(notes.len(), 1);
    assert_eq!(
        store.get(notes[0].id).unwrap().content,
        "Committed before exit"
    );
}

// Child-process helper. exit() intentionally skips destructors and SQLite close.
#[test]
fn abrupt_exit_writer() {
    let Some(path) = std::env::var_os("BETTERNOTES_CRASH_TEST_PATH") else {
        return;
    };
    let store = NoteStore::open(std::path::Path::new(&path)).unwrap();
    let mut note = store.create().unwrap();
    note.content = "Committed before exit".into();
    store.update(&note).unwrap();
    let interrupted = Connection::open(path).unwrap();
    interrupted.execute_batch("BEGIN IMMEDIATE; INSERT INTO notes (title, created_at, updated_at) VALUES ('Uncommitted', 0, 0);").unwrap();
    std::process::exit(0);
}
