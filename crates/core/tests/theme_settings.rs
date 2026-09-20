use betternotes_core::{NoteStore, NotesSession, ThemePreference};
use rusqlite::Connection;

#[test]
fn upgrade_phase_three_preserves_notes_windows_and_adds_settings() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let connection = Connection::open(&path).unwrap();
    connection
        .execute_batch(include_str!("../../../migrations/0001_notes.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../../../migrations/0002_note_windows.sql"))
        .unwrap();
    connection
        .execute_batch(
            "INSERT INTO notes (title, content, created_at, updated_at) VALUES ('Title', 'Body', 10, 20);
             INSERT INTO note_windows (note_id, x, y, width, height, screen, collapsed, is_open)
             VALUES (1, 100, 200, 400, 300, 'DP-1', 0, 1);
             PRAGMA application_id = 0x424e4f54;
             PRAGMA user_version = 2;",
        )
        .unwrap();
    drop(connection);

    let store = NoteStore::open(&path).unwrap();
    assert_eq!(store.get(1).unwrap().title, "Title");
    let window = store.window_state(1).unwrap();
    assert_eq!(window.width, 400);
    assert_eq!(window.height, 300);
    assert_eq!(window.position, Some((100, 200)));

    // Default theme is System
    assert_eq!(store.theme().unwrap(), ThemePreference::System);

    // Can set and persist theme
    store.set_theme(ThemePreference::Dark).unwrap();
    assert_eq!(store.theme().unwrap(), ThemePreference::Dark);

    drop(store);

    let reopened = NoteStore::open(&path).unwrap();
    assert_eq!(reopened.theme().unwrap(), ThemePreference::Dark);
    assert_eq!(
        reopened.get_setting("theme").unwrap().as_deref(),
        Some("dark")
    );
}

#[test]
fn session_manages_theme_preference() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();

    assert_eq!(session.theme().unwrap(), ThemePreference::System);
    session.set_theme(ThemePreference::Light).unwrap();
    assert_eq!(session.theme().unwrap(), ThemePreference::Light);

    drop(session);
    let session = NotesSession::open(&path).unwrap();
    assert_eq!(session.theme().unwrap(), ThemePreference::Light);
}

#[test]
fn theme_preference_parsing_and_formatting() {
    assert_eq!(
        "light".parse::<ThemePreference>().unwrap(),
        ThemePreference::Light
    );
    assert_eq!(
        "Dark".parse::<ThemePreference>().unwrap(),
        ThemePreference::Dark
    );
    assert_eq!(
        "SYSTEM".parse::<ThemePreference>().unwrap(),
        ThemePreference::System
    );
    assert_eq!(
        "invalid".parse::<ThemePreference>().unwrap(),
        ThemePreference::System
    );
    assert_eq!(ThemePreference::System.as_str(), "system");
    assert_eq!(ThemePreference::Light.as_str(), "light");
    assert_eq!(ThemePreference::Dark.as_str(), "dark");
}

#[test]
fn session_manages_note_appearance() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();
    session.create().unwrap();

    // Default note appearance
    assert_eq!(session.note_color(), "yellow");
    assert_eq!(session.note_font_family(), "default");
    assert_eq!(session.note_font_size(), 13);

    // Update appearance
    session.set_note_color("#8B5CF6").unwrap();
    session.set_note_font_family("Monospace").unwrap();
    session.set_note_font_size(16).unwrap();

    assert_eq!(session.note_color(), "#8B5CF6");
    assert_eq!(session.note_font_family(), "Monospace");
    assert_eq!(session.note_font_size(), 16);

    drop(session);

    let reopened = NotesSession::open(&path).unwrap();
    assert_eq!(reopened.note_color(), "#8B5CF6");
    assert_eq!(reopened.note_font_family(), "Monospace");
    assert_eq!(reopened.note_font_size(), 16);
}
