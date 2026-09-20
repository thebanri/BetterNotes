use betternotes_core::{NoteStore, NotesSession};
use rusqlite::Connection;

#[test]
fn upgrade_from_v3_to_v4_preserves_data_and_enables_fts_and_tags() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let connection = Connection::open(&path).unwrap();

    // Setup schema v3
    connection
        .execute_batch(include_str!("../../../migrations/0001_notes.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../../../migrations/0002_note_windows.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../../../migrations/0003_settings.sql"))
        .unwrap();

    connection
        .execute_batch(
            "INSERT INTO notes (title, content, created_at, updated_at)
             VALUES ('Rust Language', 'Fast and safe systems programming language.', 1000, 2000);
             PRAGMA application_id = 0x424e4f54;
             PRAGMA user_version = 3;",
        )
        .unwrap();
    drop(connection);

    let store = NoteStore::open(&path).unwrap();
    let note = store.get(1).unwrap();
    assert_eq!(note.title, "Rust Language");
    assert_eq!(note.priority, 0);
    assert!(!note.is_archived);
    assert!(!note.is_pinned);
    assert!(note.tags.is_empty());

    // FTS5 search should find the existing note
    let results = store.search("programming").unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].id, 1);
    assert_eq!(results[0].title, "Rust Language");

    let version: i64 = Connection::open(&path)
        .unwrap()
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .unwrap();
    assert!(version >= 4);
}

#[test]
fn search_fts5_indexing_and_sanitization() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();

    session.create().unwrap();
    session.edit_title("Architecture Review".to_string());
    session.edit_content("We should isolate Wayland platform abstractions.".to_string());
    session.save().unwrap();

    session.create().unwrap();
    session.edit_title("Shopping List".to_string());
    session.edit_content("Apples, bananas, and milk.".to_string());
    session.save().unwrap();

    // Query matching title
    let res = session.search("Architecture").unwrap();
    assert_eq!(res.len(), 1);
    assert_eq!(res[0].title, "Architecture Review");

    // Query matching content
    let res = session.search("Wayland").unwrap();
    assert_eq!(res.len(), 1);
    assert_eq!(res[0].title, "Architecture Review");

    // Multiple terms (AND search)
    let res = session.search("platform Wayland").unwrap();
    assert_eq!(res.len(), 1);

    // Non-matching query
    let res = session.search("Quantum").unwrap();
    assert!(res.is_empty());

    // Tricky input with quotes, brackets, and operators
    let res = session.search("NOT AND OR \" ' * ; ()").unwrap();
    // Sanitizer strips invalid characters and escapes quotes, does not error
    assert!(res.is_empty());

    // Update note content and verify FTS updates
    session.select(1).unwrap(); // Select Architecture Review
    session.edit_content("Now discussing Hyprland and Sway compositors.".to_string());
    session.save().unwrap();

    assert!(session.search("Wayland").unwrap().is_empty());
    assert_eq!(session.search("Hyprland").unwrap().len(), 1);
}

#[test]
fn tags_priorities_pinning_and_archiving() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();

    session.create().unwrap();
    session.edit_title("Critical Bug".to_string());
    session.edit_content("Memory leak in Wayland buffer.".to_string());
    session.set_priority(3).unwrap();
    session.set_pinned(true).unwrap();
    session
        .set_tags(vec!["bug".to_string(), "wayland".to_string()])
        .unwrap();
    session.save().unwrap();

    let summaries = session.summaries();
    assert_eq!(summaries.len(), 1);
    assert_eq!(summaries[0].priority, 3);
    assert!(summaries[0].is_pinned);
    assert!(!summaries[0].is_archived);
    assert_eq!(
        summaries[0].tags,
        vec!["bug".to_string(), "wayland".to_string()]
    );

    // Tag search: tags are indexed into FTS
    let res = session.search("bug").unwrap();
    assert_eq!(res.len(), 1);
    assert_eq!(res[0].title, "Critical Bug");

    // List all tags
    let tags = session.list_tags().unwrap();
    assert_eq!(tags, vec!["bug".to_string(), "wayland".to_string()]);

    // Archive the note
    session.set_archived(true).unwrap();
    session.save().unwrap();
    assert!(session.summaries()[0].is_archived);

    // Deleting note cleans up note_tags and FTS
    session.delete_current().unwrap();
    assert!(session.search("Critical").unwrap().is_empty());
    assert!(session.search("bug").unwrap().is_empty());
}
