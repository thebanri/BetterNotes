use crate::{Error, Note, NoteSummary, Result, SearchResult, ThemePreference, WindowState};
use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};
use std::{
    path::Path,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const APPLICATION_ID: i64 = 0x424e4f54; // BNOT, an internal identifier, not a public app ID.
const SCHEMA_VERSION: i64 = 6;
const INITIAL_SCHEMA: &str = include_str!("../../../migrations/0001_notes.sql");
const WINDOW_SCHEMA: &str = include_str!("../../../migrations/0002_note_windows.sql");
const SETTINGS_SCHEMA: &str = include_str!("../../../migrations/0003_settings.sql");
const SEARCH_ORG_SCHEMA: &str =
    include_str!("../../../migrations/0004_search_and_organization.sql");
const PRODUCTIVITY_SCHEMA: &str = include_str!("../../../migrations/0005_productivity.sql");
const PLAIN_SEARCH_SCHEMA: &str = include_str!("../../../migrations/0006_plain_search_text.sql");
/// Preview length for list rows and search results, in characters.
const PREVIEW_CHARS: usize = 140;
const NOTES_STAY_BELOW_KEY: &str = "notes_stay_below";
const RECENT_SEARCHES_KEY: &str = "recent_searches";
/// How many recent library searches are remembered.
pub const RECENT_SEARCH_LIMIT: usize = 8;

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
        let mut statement = self.connection.prepare(
            // Rich-text bodies open with a long `<head>`, so the preview needs
            // more raw characters than it will finally show. It stays a
            // substring: list queries never load whole note bodies.
            "SELECT n.id, n.title, substr(n.content, 1, 2000), n.priority, n.is_archived, n.is_pinned,
                    COALESCE((SELECT group_concat(t.name, ',') FROM note_tags nt JOIN tags t ON nt.tag_id = t.id WHERE nt.note_id = n.id), '')
             FROM notes n
             ORDER BY n.is_pinned DESC, n.updated_at DESC, n.id DESC",
        )?;
        let rows = statement.query_map([], |row| {
            let tags_str: String = row.get(6)?;
            let tags = if tags_str.is_empty() {
                Vec::new()
            } else {
                tags_str
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect()
            };
            let content: String = row.get(2)?;
            Ok(NoteSummary {
                id: row.get(0)?,
                title: row.get(1)?,
                snippet: crate::preview::plain_preview(&content, PREVIEW_CHARS),
                priority: row.get(3)?,
                is_archived: row.get::<_, i32>(4)? != 0,
                is_pinned: row.get::<_, i32>(5)? != 0,
                tags,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn get(&self, id: i64) -> Result<Note> {
        let note = self
            .connection
            .query_row(
                "SELECT id, title, content, created_at, updated_at, revision, priority, is_archived, is_pinned
                 FROM notes WHERE id = ?1",
                [id],
                |row| {
                    Ok((
                        row.get::<_, i64>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, i64>(3)?,
                        row.get::<_, i64>(4)?,
                        row.get::<_, i64>(5)?,
                        row.get::<_, i32>(6)?,
                        row.get::<_, i32>(7)? != 0,
                        row.get::<_, i32>(8)? != 0,
                    ))
                },
            )
            .optional()?
            .ok_or(Error::NotFound(id))?;

        let mut statement = self.connection.prepare(
            "SELECT t.name FROM note_tags nt JOIN tags t ON nt.tag_id = t.id WHERE nt.note_id = ?1 ORDER BY t.name",
        )?;
        let tags = statement
            .query_map([id], |row| row.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        Ok(Note {
            id: note.0,
            title: note.1,
            content: note.2,
            created_at: note.3,
            updated_at: note.4,
            revision: note.5,
            priority: note.6,
            is_archived: note.7,
            is_pinned: note.8,
            tags,
        })
    }

    pub fn create(&self) -> Result<Note> {
        let now = now_millis()?;
        self.connection.execute(
            "INSERT INTO notes (created_at, updated_at, priority, is_archived, is_pinned)
             VALUES (?1, ?1, 0, 0, 0)",
            [now],
        )?;
        Ok(Note {
            id: self.connection.last_insert_rowid(),
            title: String::new(),
            content: String::new(),
            created_at: now,
            updated_at: now,
            revision: 0,
            priority: 0,
            is_archived: false,
            is_pinned: false,
            tags: Vec::new(),
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
            "UPDATE notes SET title = ?1, content = ?2, updated_at = ?3, revision = ?4,
                    priority = ?5, is_archived = ?6, is_pinned = ?7, search_text = ?10
             WHERE id = ?8 AND revision = ?9",
            params![
                draft.title,
                draft.content,
                updated_at,
                revision,
                draft.priority,
                if draft.is_archived { 1 } else { 0 },
                if draft.is_pinned { 1 } else { 0 },
                draft.id,
                draft.revision,
                crate::preview::to_plain_text(&draft.content)
            ],
        )?;
        if changed != 1 {
            return Err(Error::Conflict);
        }

        self.sync_tags(draft.id, &draft.tags)?;

        Ok(Note {
            updated_at,
            revision,
            ..draft.clone()
        })
    }

    fn sync_tags(&self, note_id: i64, tags: &[String]) -> Result<()> {
        self.connection
            .execute("DELETE FROM note_tags WHERE note_id = ?1", [note_id])?;
        for tag in tags {
            let trimmed = tag.trim();
            if trimmed.is_empty() || trimmed.len() > 64 {
                continue;
            }
            self.connection
                .execute("INSERT OR IGNORE INTO tags (name) VALUES (?1)", [trimmed])?;
            let tag_id: i64 = self.connection.query_row(
                "SELECT id FROM tags WHERE name = ?1 COLLATE NOCASE",
                [trimmed],
                |row| row.get(0),
            )?;
            self.connection.execute(
                "INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?1, ?2)",
                params![note_id, tag_id],
            )?;
        }
        Ok(())
    }

    pub fn search(&self, query: &str) -> Result<Vec<SearchResult>> {
        let clean_query = sanitize_fts5_query(query);
        if clean_query.is_empty() {
            return Ok(Vec::new());
        }
        let mut statement = self.connection.prepare(
            // U+E000/U+E001 mark each match; they are private-use characters
            // no note contains, and the library turns them into highlights.
            "SELECT n.id, n.title, snippet(notes_fts, 1, char(57344), char(57345), '…', 24)
             FROM notes_fts
             JOIN notes n ON notes_fts.rowid = n.id
             WHERE notes_fts MATCH ?1
             ORDER BY rank
             LIMIT 50",
        )?;
        let rows = statement.query_map([clean_query], |row| {
            let snippet: String = row.get(2)?;
            Ok(SearchResult {
                id: row.get(0)?,
                title: row.get(1)?,
                snippet: crate::preview::plain_preview(&snippet, PREVIEW_CHARS),
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn list_tags(&self) -> Result<Vec<String>> {
        let mut stmt = self
            .connection
            .prepare("SELECT name FROM tags ORDER BY name ASC")?;
        let rows = stmt.query_map([], |row| row.get(0))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
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

    /// Every note's chosen colour, keyed by note id, in one query.
    pub fn note_colors(&self) -> Result<std::collections::HashMap<i64, String>> {
        let mut statement = self
            .connection
            .prepare("SELECT key, value FROM settings WHERE key LIKE 'note_color_%'")?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        let mut colors = std::collections::HashMap::new();
        for row in rows {
            let (key, value) = row?;
            if let Ok(id) = key["note_color_".len()..].parse::<i64>() {
                colors.insert(id, value);
            }
        }
        Ok(colors)
    }

    /// Whether unpinned sticky notes stay beneath ordinary windows. On by
    /// default: sticky notes behave like part of the desktop unless pinned.
    pub fn notes_stay_below(&self) -> Result<bool> {
        Ok(self
            .get_setting(NOTES_STAY_BELOW_KEY)?
            .is_none_or(|value| value != "false"))
    }

    pub fn set_notes_stay_below(&self, enabled: bool) -> Result<()> {
        self.set_setting(NOTES_STAY_BELOW_KEY, if enabled { "true" } else { "false" })
    }

    /// Recent library searches, newest first. Searches are single lines, so
    /// they are stored one per line.
    pub fn recent_searches(&self) -> Result<Vec<String>> {
        Ok(self
            .get_setting(RECENT_SEARCHES_KEY)?
            .unwrap_or_default()
            .lines()
            .filter(|line| !line.trim().is_empty())
            .map(str::to_string)
            .collect())
    }

    /// Puts a search first in the recent list, once, keeping the newest few.
    pub fn remember_search(&self, query: &str) -> Result<()> {
        let query = query.split_whitespace().collect::<Vec<_>>().join(" ");
        if query.is_empty() {
            return Ok(());
        }
        let lower = query.to_lowercase();
        let mut searches = self.recent_searches()?;
        searches.retain(|search| search.to_lowercase() != lower);
        searches.insert(0, query);
        searches.truncate(RECENT_SEARCH_LIMIT);
        self.set_setting(RECENT_SEARCHES_KEY, &searches.join("\n"))
    }

    pub fn clear_recent_searches(&self) -> Result<()> {
        self.set_setting(RECENT_SEARCHES_KEY, "")
    }

    pub fn raw_connection(&self) -> &Connection {
        &self.connection
    }

    pub fn all_notes_for_export(&self) -> Result<Vec<crate::export_import::ExportNote>> {
        let mut statement = self.connection.prepare(
            "SELECT n.title, n.content, n.priority, n.is_archived, n.is_pinned, n.created_at, n.updated_at,
                    COALESCE((SELECT group_concat(t.name, ',') FROM note_tags nt JOIN tags t ON nt.tag_id = t.id WHERE nt.note_id = n.id), '')
             FROM notes n
             ORDER BY n.id ASC",
        )?;
        let rows = statement.query_map([], |row| {
            let tags_str: String = row.get(7)?;
            let tags = if tags_str.is_empty() {
                Vec::new()
            } else {
                tags_str
                    .split(',')
                    .map(|s| s.trim().to_string())
                    .filter(|s| !s.is_empty())
                    .collect()
            };
            Ok(crate::export_import::ExportNote {
                title: row.get(0)?,
                content: row.get(1)?,
                priority: row.get(2)?,
                is_archived: row.get::<_, i32>(3)? != 0,
                is_pinned: row.get::<_, i32>(4)? != 0,
                created_at: row.get(5)?,
                updated_at: row.get(6)?,
                tags,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
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
    }
    transaction.prepare("SELECT key, value FROM settings LIMIT 0")?;
    if version < 4 {
        transaction.execute_batch(SEARCH_ORG_SCHEMA)?;
    }
    transaction.prepare("SELECT rowid, title, content, tags FROM notes_fts LIMIT 0")?;
    transaction.prepare("SELECT id, name FROM tags LIMIT 0")?;
    transaction.prepare("SELECT note_id, tag_id FROM note_tags LIMIT 0")?;
    if version < 5 {
        transaction.execute_batch(PRODUCTIVITY_SCHEMA)?;
    }
    transaction
        .prepare("SELECT id, note_id, remind_at, recurrence, dismissed FROM reminders LIMIT 0")?;
    transaction.prepare("SELECT id, note_id, filename, mime_type, byte_size, stored_rel_path FROM attachments LIMIT 0")?;
    if version < 6 {
        transaction.execute_batch(PLAIN_SEARCH_SCHEMA)?;
        // Fill search_text from the stored bodies; the update trigger then
        // reindexes each note from its plain text.
        let notes: Vec<(i64, String)> = {
            let mut statement = transaction.prepare("SELECT id, content FROM notes")?;
            let rows = statement.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?;
            rows.collect::<rusqlite::Result<_>>()?
        };
        for (id, content) in notes {
            transaction.execute(
                "UPDATE notes SET search_text = ?1 WHERE id = ?2",
                params![crate::preview::to_plain_text(&content), id],
            )?;
        }
    }
    transaction.prepare("SELECT search_text FROM notes LIMIT 0")?;
    if version < SCHEMA_VERSION {
        transaction.pragma_update(None, "user_version", SCHEMA_VERSION)?;
    }
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

fn sanitize_fts5_query(input: &str) -> String {
    let terms: Vec<String> = input
        .split_whitespace()
        .filter_map(|w| {
            let cleaned: String = w
                .chars()
                .filter(|c| c.is_alphanumeric() || *c == '_' || *c == '-')
                .collect();
            if cleaned.is_empty() {
                None
            } else {
                Some(format!("\"{}\"*", cleaned.replace('"', "\"\"")))
            }
        })
        .collect();
    terms.join(" ")
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
