use crate::{Error, Note, NoteSummary, Result};
use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};
use std::{
    path::Path,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const APPLICATION_ID: i64 = 0x424e4f54; // BNOT, an internal identifier, not a public app ID.
const SCHEMA_VERSION: i64 = 1;
const INITIAL_SCHEMA: &str = include_str!("../../../migrations/0001_notes.sql");

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
        transaction.pragma_update(None, "user_version", SCHEMA_VERSION)?;
    } else if application_id != APPLICATION_ID {
        return Err(Error::UnrecognizedDatabase);
    }
    // Reject incomplete schemas without ever resetting existing data.
    transaction.prepare(
        "SELECT id, title, content, created_at, updated_at, revision FROM notes LIMIT 0",
    )?;
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
