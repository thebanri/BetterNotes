use betternotes_core::{
    add_attachment, clear_reminder_for_note, create_backup, delete_attachment,
    dismiss_or_advance_reminder, export_notes_json, export_notes_markdown_dir, get_due_reminders,
    get_reminder_for_note, import_note_markdown_file, import_notes_json, list_attachments,
    restore_backup, set_reminder, NoteStore, Recurrence,
};
use std::fs;
use tempfile::tempdir;

#[test]
fn upgrade_to_v5_and_reminders_lifecycle() {
    let dir = tempdir().unwrap();
    let db_path = dir.path().join("notes.sqlite3");
    let store = NoteStore::open(&db_path).unwrap();

    let note = store.create().unwrap();
    let note_id = note.id;

    // Set reminder
    let now = 1_700_000_000;
    let rem_id = set_reminder(
        store.raw_connection(),
        note_id,
        now + 100,
        Recurrence::Daily,
    )
    .unwrap();
    assert!(rem_id > 0);

    let active = get_reminder_for_note(store.raw_connection(), note_id)
        .unwrap()
        .unwrap();
    assert_eq!(active.remind_at, now + 100);
    assert_eq!(active.recurrence, Recurrence::Daily);
    assert!(!active.dismissed);

    // Query due reminders before time: empty
    let due_before = get_due_reminders(store.raw_connection(), now).unwrap();
    assert!(due_before.is_empty());

    // Query due reminders at due time: 1
    let due = get_due_reminders(store.raw_connection(), now + 100).unwrap();
    assert_eq!(due.len(), 1);
    assert_eq!(due[0].note_id, note_id);

    // Dismiss recurring reminder -> advances to next day
    dismiss_or_advance_reminder(store.raw_connection(), rem_id).unwrap();
    let advanced = get_reminder_for_note(store.raw_connection(), note_id)
        .unwrap()
        .unwrap();
    assert_eq!(advanced.remind_at, now + 100 + 86400);

    // Clear reminder
    clear_reminder_for_note(store.raw_connection(), note_id).unwrap();
    assert!(get_reminder_for_note(store.raw_connection(), note_id)
        .unwrap()
        .is_none());
}

#[test]
fn attachments_crud_and_safety() {
    let dir = tempdir().unwrap();
    let db_path = dir.path().join("notes.sqlite3");
    let store = NoteStore::open(&db_path).unwrap();

    let note = store.create().unwrap();
    let note_id = note.id;

    // Create a dummy file to attach
    let sample_file = dir.path().join("spec.pdf");
    fs::write(&sample_file, b"%PDF-1.4 sample content").unwrap();

    let att = add_attachment(dir.path(), store.raw_connection(), note_id, &sample_file).unwrap();
    assert_eq!(att.filename, "spec.pdf");
    assert_eq!(att.mime_type, "application/pdf");
    assert_eq!(att.byte_size, 23);

    let list = list_attachments(store.raw_connection(), note_id).unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].id, att.id);

    // Delete attachment
    delete_attachment(dir.path(), store.raw_connection(), &att.id).unwrap();
    let empty_list = list_attachments(store.raw_connection(), note_id).unwrap();
    assert!(empty_list.is_empty());
}

#[test]
fn export_and_import_json_and_markdown() {
    let dir = tempdir().unwrap();
    let db_path = dir.path().join("notes.sqlite3");
    let store = NoteStore::open(&db_path).unwrap();

    let mut note1 = store.create().unwrap();
    note1.title = "Architecture Plan".into();
    note1.content = "Modular Linux-first workspace".into();
    note1.tags = vec!["linux".into(), "rust".into()];
    note1.priority = 2;
    note1.is_pinned = true;
    store.update(&note1).unwrap();

    let mut note2 = store.create().unwrap();
    note2.title = "Grocery list".into();
    note2.content = "Apples\nMilk".into();
    store.update(&note2).unwrap();

    // Export all notes to JSON
    let export_list = store.all_notes_for_export().unwrap();
    assert_eq!(export_list.len(), 2);

    let json_file = dir.path().join("export.json");
    export_notes_json(&export_list, &json_file).unwrap();
    assert!(json_file.exists());

    // Import into a new store
    let new_dir = tempdir().unwrap();
    let new_db = new_dir.path().join("notes.sqlite3");
    let new_store = NoteStore::open(&new_db).unwrap();

    let count = import_notes_json(&new_store, &json_file).unwrap();
    assert_eq!(count, 2);

    let imported_list = new_store.list().unwrap();
    assert_eq!(imported_list.len(), 2);
    assert!(imported_list[0].is_pinned); // note1 was pinned
    assert_eq!(imported_list[0].title, "Architecture Plan");
    assert_eq!(imported_list[0].tags, vec!["linux", "rust"]);

    // Test Markdown export & import
    let md_dir = dir.path().join("md_export");
    export_notes_markdown_dir(&export_list, &md_dir).unwrap();
    let md_files: Vec<_> = fs::read_dir(&md_dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .collect();
    assert_eq!(md_files.len(), 2);

    let md_note_count = import_note_markdown_file(&new_store, &md_files[0]).unwrap();
    assert_eq!(md_note_count, 1);
}

#[test]
fn backup_and_restore_cycle() {
    let source_dir = tempdir().unwrap();
    let db_path = source_dir.path().join("notes.sqlite3");
    let store = NoteStore::open(&db_path).unwrap();

    let mut note = store.create().unwrap();
    note.title = "Critical Backup Note".into();
    note.content = "Must survive backup and restore".into();
    store.update(&note).unwrap();

    // Add an attachment
    let sample = source_dir.path().join("photo.png");
    fs::write(&sample, b"fakepngdata").unwrap();
    add_attachment(source_dir.path(), store.raw_connection(), note.id, &sample).unwrap();

    // Create backup
    let backups_parent = tempdir().unwrap();
    let backup_path = create_backup(
        store.raw_connection(),
        source_dir.path(),
        backups_parent.path(),
    )
    .unwrap();
    assert!(backup_path.join("notes.sqlite3").is_file());
    assert!(backup_path.join("manifest.json").is_file());
    assert!(backup_path.join("attachments").is_dir());

    // Restore to another fresh target
    let target_dir = tempdir().unwrap();
    restore_backup(&backup_path, target_dir.path()).unwrap();

    let restored_store = NoteStore::open(&target_dir.path().join("notes.sqlite3")).unwrap();
    let notes = restored_store.list().unwrap();
    assert_eq!(notes.len(), 1);
    assert_eq!(notes[0].title, "Critical Backup Note");

    let restored_att = list_attachments(restored_store.raw_connection(), notes[0].id).unwrap();
    assert_eq!(restored_att.len(), 1);
    assert_eq!(restored_att[0].filename, "photo.png");
}
