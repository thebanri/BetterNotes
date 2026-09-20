use crate::{Error, Note, NoteSummary, Result, ThemePreference, WindowState};
use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};
use std::{
    path::Path,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const APPLICATION_ID: i64 = 0x424e4f54; // BNOT, an internal identifier, not a public app ID.
const SCHEMA_VERSION: i64 = 3;
const INITIAL_SCHEMA: &str = include_str!("../../../migrations/0001_notes.sql");
const WINDOW_SCHEMA: &str = include_str!("../../../migrations/0002_note_windows.sql");
const SETTINGS_SCHEMA: &str = include_str!("../../../migrations/0003_settings.sql");

pub struct NoteStore {
    connection: Connection,
}

impl NoteStore {
    /// Errors never trigger deletion, replacement or a fallback to volatile storage.
    pub fn open(path: &Path) -> Result<Self> {
        let mut connection = Connection::open(path)?;
        // Bound synchronous GUI waits when another process holds the write lock.
        connection.busy_timeout(Duration::from_millis(250))?;
        connection.pragma_update(None, "foreign_keys", true)?;
        migrate(&mut connection, INITIAL_SCHEMA)?;
        connection.pragma_update(None, "journal_mode", "WAL")?;
        connection.pragma_update(None, "synchronous", "FULL")?;
        Ok(Self { connection })
    }

    pub fn list(&self) -> Result<Vec<NoteSummary>> {
        let mut statement = self
            .connection
            .prepare("SELECT id, title FROM notes ORDER BY id DESC")?;
        let rows = statement.query_map([], |row| {
            Ok(NoteSummary {
                id: row.get(0)?,
                title: row.get(1)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn get(&self, id: i64) -> Result<Note> {
        self.connection
            .query_row(
                "SELECT id, title, content, created_at, updated_at, revision FROM notes WHERE id = ?1",
                [id],
                |row| {
                    Ok(Note {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        content: row.get(2)?,
                        created_at: row.get(3)?,
                        updated_at: row.get(4)?,
                        revision: row.get(5)?,
                    })
                },
            )
            .optional()?
            .ok_or(Error::NotFound(id))
    }

    pub fn create(&self) -> Result<Note> {
        let now = now_millis()?;
        self.connection.execute(
            "INSERT INTO notes (created_at, updated_at) VALUES (?1, ?1)",
            [now],
        )?;
        Ok(Note {
            id: self.connection.last_insert_rowid(),
            title: String::new(),
            content: String::new(),
            created_at: now,
            updated_at: now,
            revision: 0,
        })
    }

    /// A single conditional statement commits the entire draft atomically.
    pub fn update(&self, draft: &Note) -> Result<Note> {
        let revision = draft
            .revision
            .checked_add(1)
            .ok_or(Error::RevisionOverflow)?;
        let updated_at = now_millis()?.max(draft.updated_at);
        let changed = self.connection.execute(
            "UPDATE notes SET title = ?1, content = ?2, updated_at = ?3, revision = ?4
             WHERE id = ?5 AND revision = ?6",
            params![
                draft.title,
                draft.content,
                updated_at,
                revision,
                draft.id,
                draft.revision
            ],
        )?;
        if changed != 1 {
            return Err(Error::Conflict);
        }
        Ok(Note {
            updated_at,
            revision,
            ..draft.clone()
        })
    }

    pub fn delete(&self, note: &Note) -> Result<()> {
        let changed = self.connection.execute(
            "DELETE FROM notes WHERE id = ?1 AND revision = ?2",
            params![note.id, note.revision],
        )?;
        if changed != 1 {
            return Err(Error::Conflict);
        }
        Ok(())
    }

    pub fn window_state(&self, note_id: i64) -> Result<WindowState> {
        let state = self.connection.query_row(
            "SELECT x, y, width, height, screen, collapsed, is_open FROM note_windows WHERE note_id = ?1",
            [note_id],
            |row| Ok(WindowState {
                position: row.get::<_, Option<i32>>(0)?.zip(row.get(1)?),
                width: row.get(2)?, height: row.get(3)?, screen: row.get(4)?,
                collapsed: row.get(5)?, open: row.get(6)?,
            }),
        ).optional()?.unwrap_or_default();
        state.validate()?;
        Ok(state)
    }

    /// Separate from content revisions: resizing must not cause edit conflicts.
    pub fn save_window_state(&self, note_id: i64, state: &WindowState) -> Result<()> {
        state.validate()?;
        self.connection.execute(
            "INSERT INTO note_windows (note_id, x, y, width, height, screen, collapsed, is_open)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
             ON CONFLICT(note_id) DO UPDATE SET x=excluded.x, y=excluded.y,
             width=excluded.width, height=excluded.height, screen=excluded.screen,
             collapsed=excluded.collapsed, is_open=excluded.is_open",
            params![
                note_id,
                state.position.map(|p| p.0),
                state.position.map(|p| p.1),
                state.width,
                state.height,
                state.screen,
                state.collapsed,
                state.open
            ],
        )?;
        Ok(())
    }

    pub fn open_window_ids(&self) -> Result<Vec<i64>> {
        let mut statement = self
            .connection
            .prepare("SELECT note_id FROM note_windows WHERE is_open = 1 ORDER BY note_id")?;
        let rows = statement.query_map([], |row| row.get(0))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn get_setting(&self, key: &str) -> Result<Option<String>> {
        let val = self
            .connection
            .query_row("SELECT value FROM settings WHERE key = ?1", [key], |row| {
                row.get(0)
            })
            .optional()?;
        Ok(val)
    }

    pub fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.connection.execute(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn theme(&self) -> Result<ThemePreference> {
        let pref = self
            .get_setting("theme")?
            .unwrap_or_else(|| "system".to_string());
        Ok(pref.parse().unwrap_or_default())
    }

    pub fn set_theme(&self, theme: ThemePreference) -> Result<()> {
        self.set_setting("theme", theme.as_str())
    }
}

fn migrate(connection: &mut Connection, initial_schema: &str) -> Result<()> {
    let transaction = connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let version: i64 = transaction.pragma_query_value(None, "user_version", |row| row.get(0))?;
    let application_id: i64 =
        transaction.pragma_query_value(None, "application_id", |row| row.get(0))?;
    if !(0..=SCHEMA_VERSION).contains(&version) {
        return Err(Error::UnsupportedSchema(version));
    }
    if version == 0 {
        let tables: i64 = transaction.query_row(
            "SELECT count(*) FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*'",
            [],
            |row| row.get(0),
        )?;
        if application_id != 0 || tables != 0 {
            return Err(Error::UnrecognizedDatabase);
        }
        transaction.execute_batch(initial_schema)?;
        transaction.pragma_update(None, "application_id", APPLICATION_ID)?;
    } else if application_id != APPLICATION_ID {
        return Err(Error::UnrecognizedDatabase);
    }
    // Reject incomplete schemas without ever resetting existing data.
    transaction.prepare(
        "SELECT id, title, content, created_at, updated_at, revision FROM notes LIMIT 0",
    )?;
    if version < 2 {
        transaction.execute_batch(WINDOW_SCHEMA)?;
    }
    transaction.prepare(
        "SELECT note_id, x, y, width, height, screen, collapsed, is_open FROM note_windows LIMIT 0",
    )?;
    if version < 3 {
        transaction.execute_batch(SETTINGS_SCHEMA)?;
        transaction.pragma_update(None, "user_version", SCHEMA_VERSION)?;
    }
    transaction.prepare("SELECT key, value FROM settings LIMIT 0")?;
    transaction.commit()?;
    Ok(())
}

fn now_millis() -> Result<i64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| Error::Clock)?
        .as_millis()
        .try_into()
        .map_err(|_| Error::Clock)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failed_migration_rolls_back_schema_and_version() {
        let mut connection = Connection::open_in_memory().unwrap();
        assert!(migrate(
            &mut connection,
            "CREATE TABLE partial (id INTEGER); INVALID SQL;"
        )
        .is_err());
        let count: i64 = connection
            .query_row("SELECT count(*) FROM sqlite_schema", [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 0);
        let version: i64 = connection
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(version, 0);
        migrate(&mut connection, INITIAL_SCHEMA).unwrap();
        migrate(&mut connection, INITIAL_SCHEMA).unwrap();
    }
}
