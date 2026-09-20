use betternotes_core::{Error, NoteStore, NotesSession, WindowState};
use rusqlite::Connection;

#[test]
fn upgrade_phase_two_preserves_notes_and_is_repeatable() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let connection = Connection::open(&path).unwrap();
    connection
        .execute_batch(include_str!("../../../migrations/0001_notes.sql"))
        .unwrap();
    connection.execute_batch("INSERT INTO notes (title, content, created_at, updated_at) VALUES ('Existing', 'Keep me', 1, 2); PRAGMA application_id=0x424e4f54; PRAGMA user_version=1;").unwrap();
    drop(connection);
    let store = NoteStore::open(&path).unwrap();
    let original = store.get(1).unwrap();
    assert_eq!(original.content, "Keep me");
    assert_eq!(store.window_state(1).unwrap(), WindowState::default());
    assert!(store.open_window_ids().unwrap().is_empty());
    drop(store);
    assert_eq!(NoteStore::open(&path).unwrap().get(1).unwrap(), original);
    let connection = Connection::open(&path).unwrap();
    assert_eq!(
        connection
            .pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
            .unwrap(),
        3
    );
}

#[test]
fn failed_phase_three_migration_keeps_version_and_existing_data() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let connection = Connection::open(&path).unwrap();
    connection
        .execute_batch(include_str!("../../../migrations/0001_notes.sql"))
        .unwrap();
    connection.execute_batch("INSERT INTO notes (content, created_at, updated_at) VALUES ('Keep', 0, 0); CREATE TABLE note_windows (precious TEXT); INSERT INTO note_windows VALUES ('Also keep'); PRAGMA application_id=0x424e4f54; PRAGMA user_version=1;").unwrap();
    assert!(NoteStore::open(&path).is_err());
    assert_eq!(
        connection
            .pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
            .unwrap(),
        1
    );
    assert_eq!(
        connection
            .query_row("SELECT content FROM notes", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "Keep"
    );
    assert_eq!(
        connection
            .query_row("SELECT precious FROM note_windows", [], |r| r
                .get::<_, String>(0))
            .unwrap(),
        "Also keep"
    );
}

#[test]
fn multiple_windows_survive_reopen_and_close_is_not_delete() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let store = NoteStore::open(&path).unwrap();
    let first = store.create().unwrap();
    let second = store.create().unwrap();
    let state = WindowState {
        position: Some((-1200, 80)),
        width: 420,
        height: 500,
        screen: "DP-2".into(),
        collapsed: true,
        open: true,
    };
    store.save_window_state(first.id, &state).unwrap();
    // Wayland state deliberately has no absolute coordinates.
    let mut other = WindowState {
        open: true,
        ..WindowState::default()
    };
    store.save_window_state(second.id, &other).unwrap();
    drop(store);
    let store = NoteStore::open(&path).unwrap();
    assert_eq!(store.window_state(first.id).unwrap(), state);
    assert_eq!(store.window_state(second.id).unwrap(), other);
    assert_eq!(store.open_window_ids().unwrap(), [first.id, second.id]);
    other.open = false;
    store.save_window_state(second.id, &other).unwrap();
    assert_eq!(store.open_window_ids().unwrap(), [first.id]);
    assert_eq!(store.get(second.id).unwrap(), second);
    store.delete(&first).unwrap();
    assert!(store.open_window_ids().unwrap().is_empty());
    let connection = Connection::open(&path).unwrap();
    assert_eq!(
        connection
            .query_row(
                "SELECT count(*) FROM note_windows WHERE note_id=?1",
                [first.id],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
        0
    );
}

#[test]
fn independent_editors_and_geometry_do_not_conflict_and_deleted_reload_does_not_switch_notes() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let store = NoteStore::open(&path).unwrap();
    let first = store.create().unwrap();
    let second = store.create().unwrap();
    let mut a = NotesSession::open_note(&path, first.id).unwrap();
    let mut b = NotesSession::open_note(&path, second.id).unwrap();
    a.edit_content("First draft".into());
    b.edit_content("Second draft".into());
    a.save_window_state(&WindowState {
        open: true,
        ..WindowState::default()
    })
    .unwrap();
    a.save().unwrap();
    b.save().unwrap();
    assert_eq!(store.get(first.id).unwrap().content, "First draft");
    assert_eq!(store.get(second.id).unwrap().content, "Second draft");
    assert_eq!(store.get(first.id).unwrap().revision, 1);
    a.edit_content("Retain on reload error".into());
    store.delete(&store.get(first.id).unwrap()).unwrap();
    assert!(matches!(a.reload_note(), Err(Error::NotFound(_))));
    assert_eq!(a.current().unwrap().id, first.id);
    assert_eq!(a.current().unwrap().content, "Retain on reload error");
    assert!(a.dirty());
}

#[test]
fn invalid_and_locked_window_writes_preserve_previous_state_and_content() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let store = NoteStore::open(&path).unwrap();
    let note = store.create().unwrap();
    let original = WindowState {
        open: true,
        ..WindowState::default()
    };
    store.save_window_state(note.id, &original).unwrap();
    let invalid = WindowState {
        width: -1,
        ..original.clone()
    };
    assert!(matches!(
        store.save_window_state(note.id, &invalid),
        Err(Error::InvalidWindowState)
    ));
    let connection = Connection::open(&path).unwrap();
    connection.execute_batch("BEGIN IMMEDIATE").unwrap();
    assert!(store
        .save_window_state(note.id, &WindowState::default())
        .is_err());
    connection.execute_batch("ROLLBACK").unwrap();
    assert_eq!(store.window_state(note.id).unwrap(), original);
    assert_eq!(store.get(note.id).unwrap(), note);
    assert!(store.save_window_state(999, &original).is_err());
}
