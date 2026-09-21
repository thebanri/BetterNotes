use betternotes_core::{
    add_attachment, get_due_reminders, set_reminder, stored_path, NotesSession, Recurrence,
    WindowState,
};

#[test]
fn trash_hides_restores_and_deletes_notes_for_good() {
    let directory = tempfile::tempdir().unwrap();
    // delete_forever finds attachment files under XDG_DATA_HOME.
    std::env::set_var("XDG_DATA_HOME", directory.path());
    let data_dir = directory.path().join("betternotes");
    std::fs::create_dir_all(&data_dir).unwrap();
    let path = data_dir.join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();

    session.create().unwrap();
    session.edit_title("Keep".into());
    session.edit_content("zeppelin in keep".into());
    session.save().unwrap();
    let keep = session.current().unwrap().id;
    session.create().unwrap();
    session.edit_title("Bin".into());
    session.edit_content("zeppelin in bin".into());
    session.save().unwrap();
    let bin = session.current().unwrap().id;

    let store = session.store();
    let open = WindowState {
        open: true,
        ..WindowState::default()
    };
    store.save_window_state(bin, &open).unwrap();
    set_reminder(store.raw_connection(), bin, 10, Recurrence::None).unwrap();
    let source = directory.path().join("file.txt");
    std::fs::write(&source, "data").unwrap();
    let attachment = add_attachment(&data_dir, store.raw_connection(), bin, &source).unwrap();
    let attachment_file = stored_path(&data_dir, &attachment);
    assert!(attachment_file.exists());

    session.trash_note(bin).unwrap();
    assert_eq!(session.summaries().len(), 1);
    assert_eq!(session.summaries()[0].id, keep);
    let trash = session.trash().unwrap();
    assert_eq!(trash.len(), 1);
    assert_eq!(trash[0].0.id, bin);
    assert_eq!(trash[0].0.snippet, "zeppelin in bin");
    assert!(trash[0].1 > 0);
    let found: Vec<i64> = session
        .search("zeppelin")
        .unwrap()
        .iter()
        .map(|r| r.id)
        .collect();
    assert_eq!(found, [keep]);
    assert!(session.open_window_ids().unwrap().is_empty());
    assert!(get_due_reminders(session.store().raw_connection(), 100)
        .unwrap()
        .is_empty());

    session.restore_note(bin).unwrap();
    assert_eq!(session.summaries().len(), 2);
    assert!(session.trash().unwrap().is_empty());

    session.trash_note(bin).unwrap();
    // Only notes trashed before the cutoff are purged.
    assert_eq!(session.empty_trash(Some(0)).unwrap(), 0);
    assert_eq!(session.empty_trash(None).unwrap(), 1);
    assert!(session.trash().unwrap().is_empty());
    assert!(!attachment_file.exists(), "attachment file left behind");
    assert!(session.store().get(bin).is_err());
    assert!(session.restore_note(bin).is_err());
    assert!(
        session.delete_forever(keep).is_err(),
        "deleted a note that is not in the trash"
    );
    assert_eq!(session.summaries().len(), 1);

    session.add_note_tag(keep, "#Work").unwrap();
    session.add_note_tag(keep, "work").unwrap();
    assert_eq!(session.store().get(keep).unwrap().tags, ["Work"]);
}
