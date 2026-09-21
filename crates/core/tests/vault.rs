use betternotes_core::{
    export_import::{export_notes_json, import_notes_json},
    vault, Error, NotesSession,
};

// One test: the unlocked key is process-wide, so the steps must not run in
// parallel with each other.
#[test]
fn locked_notes_are_sealed_hidden_and_need_the_password() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();
    session.create().unwrap();
    session.edit_title("Bank".into());
    session.edit_content("PIN 4821 zeppelin".into());
    session.save().unwrap();
    let id = session.current().unwrap().id;

    // Locking needs a password first.
    assert!(!vault::is_set(session.store()).unwrap());
    assert!(matches!(session.set_locked(true), Err(Error::Locked)));
    assert!(vault::set_up(session.store(), "short").is_err());
    vault::set_up(session.store(), "correct horse").unwrap();
    assert!(vault::is_set(session.store()).unwrap());
    assert!(vault::set_up(session.store(), "another pass").is_err());
    session.set_locked(true).unwrap();

    // Stored sealed, not searchable, no preview.
    let raw: String = session
        .store()
        .raw_connection()
        .query_row("SELECT content FROM notes WHERE id = ?1", [id], |row| {
            row.get(0)
        })
        .unwrap();
    assert!(raw.starts_with(vault::SEALED_PREFIX) && !raw.contains("4821"));
    assert!(session.search("zeppelin").unwrap().is_empty());
    assert_eq!(
        session.search("Bank").unwrap().len(),
        1,
        "the title stays searchable"
    );
    session.reload().unwrap();
    let summary = session.summaries().iter().find(|s| s.id == id).unwrap();
    assert!(summary.is_locked && summary.snippet.is_empty());
    assert_eq!(
        session.store().get(id).unwrap().content,
        "PIN 4821 zeppelin"
    );

    // Locked: nothing reads or overwrites it.
    vault::lock();
    assert!(matches!(session.store().get(id), Err(Error::Locked)));
    let mut draft = session.current().unwrap().clone();
    draft.content = String::new();
    assert!(matches!(session.store().update(&draft), Err(Error::Locked)));
    assert!(!vault::unlock(session.store(), "wrong password").unwrap());
    assert!(!vault::is_unlocked());
    assert!(vault::unlock(session.store(), "correct horse").unwrap());
    assert_eq!(
        session.store().get(id).unwrap().content,
        "PIN 4821 zeppelin"
    );

    // A new password reseals every locked note.
    assert!(vault::change_password(session.store(), "wrong", "new password 1").is_err());
    vault::change_password(session.store(), "correct horse", "new password 1").unwrap();
    vault::lock();
    assert!(!vault::unlock(session.store(), "correct horse").unwrap());
    assert!(vault::unlock(session.store(), "new password 1").unwrap());
    assert_eq!(
        session.store().get(id).unwrap().content,
        "PIN 4821 zeppelin"
    );

    // Exports keep it sealed; importing brings it back locked.
    let export = directory.path().join("export.json");
    export_notes_json(&session.store().all_notes_for_export().unwrap(), &export).unwrap();
    let text = std::fs::read_to_string(&export).unwrap();
    assert!(!text.contains("4821") && text.contains("\"locked\": true"));
    let other = NotesSession::open(&directory.path().join("other.sqlite3")).unwrap();
    // The other database has no password of its own; the key is the same.
    import_notes_json(other.store(), &export).unwrap();
    let imported = other.store().list().unwrap();
    assert!(imported[0].is_locked);
    assert_eq!(
        other.store().get(imported[0].id).unwrap().content,
        "PIN 4821 zeppelin"
    );

    // Removing the lock stores the text readable again.
    session.set_locked(false).unwrap();
    assert_eq!(session.search("zeppelin").unwrap().len(), 1);
    vault::lock();
    assert_eq!(
        session.store().get(id).unwrap().content,
        "PIN 4821 zeppelin"
    );
}
