//! Reminders and recurring notifications for BetterNotes.

use crate::{Error, Result};
use rusqlite::{params, Connection, OptionalExtension};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Recurrence {
    None,
    Daily,
    Weekly,
    Monthly,
}

impl Recurrence {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::None => "none",
            Self::Daily => "daily",
            Self::Weekly => "weekly",
            Self::Monthly => "monthly",
        }
    }

    pub fn parse(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "daily" => Self::Daily,
            "weekly" => Self::Weekly,
            "monthly" => Self::Monthly,
            _ => Self::None,
        }
    }

    pub fn next_timestamp(&self, current: i64) -> Option<i64> {
        match self {
            Self::None => None,
            Self::Daily => Some(current + 86_400),
            Self::Weekly => Some(current + 604_800),
            Self::Monthly => Some(current + 2_592_000), // 30-day approximation
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reminder {
    pub id: i64,
    pub note_id: i64,
    pub remind_at: i64,
    pub recurrence: Recurrence,
    pub dismissed: bool,
    pub created_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DueReminder {
    pub reminder_id: i64,
    pub note_id: i64,
    pub note_title: String,
    pub remind_at: i64,
    pub recurrence: Recurrence,
}

pub fn set_reminder(
    connection: &Connection,
    note_id: i64,
    remind_at: i64,
    recurrence: Recurrence,
) -> Result<i64> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| Error::Clock)?
        .as_secs() as i64;

    // Delete existing active reminder for note before setting new one
    connection.execute("DELETE FROM reminders WHERE note_id = ?1", [note_id])?;

    connection.execute(
        "INSERT INTO reminders (note_id, remind_at, recurrence, dismissed, created_at)
         VALUES (?1, ?2, ?3, 0, ?4)",
        params![note_id, remind_at, recurrence.as_str(), now],
    )?;

    Ok(connection.last_insert_rowid())
}

pub fn get_reminder_for_note(connection: &Connection, note_id: i64) -> Result<Option<Reminder>> {
    let reminder = connection
        .query_row(
            "SELECT id, note_id, remind_at, recurrence, dismissed, created_at
         FROM reminders WHERE note_id = ?1 AND dismissed = 0",
            [note_id],
            |row| {
                let rec_str: String = row.get(3)?;
                Ok(Reminder {
                    id: row.get(0)?,
                    note_id: row.get(1)?,
                    remind_at: row.get(2)?,
                    recurrence: Recurrence::parse(&rec_str),
                    dismissed: row.get::<_, i32>(4)? != 0,
                    created_at: row.get(5)?,
                })
            },
        )
        .optional()?;
    Ok(reminder)
}

pub fn clear_reminder_for_note(connection: &Connection, note_id: i64) -> Result<()> {
    connection.execute("DELETE FROM reminders WHERE note_id = ?1", [note_id])?;
    Ok(())
}

pub fn get_due_reminders(connection: &Connection, now_sec: i64) -> Result<Vec<DueReminder>> {
    let mut stmt = connection.prepare(
        "SELECT r.id, r.note_id, n.title, r.remind_at, r.recurrence
         FROM reminders r
         JOIN notes n ON r.note_id = n.id
         WHERE r.dismissed = 0 AND r.remind_at <= ?1
         ORDER BY r.remind_at ASC",
    )?;
    let rows = stmt.query_map([now_sec], |row| {
        let rec_str: String = row.get(4)?;
        Ok(DueReminder {
            reminder_id: row.get(0)?,
            note_id: row.get(1)?,
            note_title: row.get(2)?,
            remind_at: row.get(3)?,
            recurrence: Recurrence::parse(&rec_str),
        })
    })?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
}

pub fn dismiss_or_advance_reminder(connection: &Connection, reminder_id: i64) -> Result<()> {
    let (recurrence_str, remind_at): (String, i64) = connection.query_row(
        "SELECT recurrence, remind_at FROM reminders WHERE id = ?1",
        [reminder_id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    let recurrence = Recurrence::parse(&recurrence_str);
    if let Some(next_at) = recurrence.next_timestamp(remind_at) {
        connection.execute(
            "UPDATE reminders SET remind_at = ?1, dismissed = 0 WHERE id = ?2",
            params![next_at, reminder_id],
        )?;
    } else {
        connection.execute(
            "UPDATE reminders SET dismissed = 1 WHERE id = ?1",
            [reminder_id],
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recurrence_intervals() {
        assert_eq!(Recurrence::Daily.as_str(), "daily");
        assert_eq!(Recurrence::Weekly.as_str(), "weekly");
        assert_eq!(Recurrence::Monthly.as_str(), "monthly");
        assert_eq!(Recurrence::None.as_str(), "none");

        assert_eq!(Recurrence::Daily.next_timestamp(1000), Some(1000 + 86400));
        assert_eq!(Recurrence::Weekly.next_timestamp(1000), Some(1000 + 604800));
        assert_eq!(Recurrence::None.next_timestamp(1000), None);
    }
}
