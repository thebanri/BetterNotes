-- Reminders table
CREATE TABLE reminders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    remind_at INTEGER NOT NULL, -- Unix timestamp in seconds
    recurrence TEXT NOT NULL DEFAULT 'none', -- 'none', 'daily', 'weekly', 'monthly'
    dismissed INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
);

CREATE INDEX idx_reminders_active ON reminders(dismissed, remind_at);
CREATE INDEX idx_reminders_note ON reminders(note_id);

-- Attachments table (metadata only; actual files stored in attachments directory)
CREATE TABLE attachments (
    id TEXT PRIMARY KEY,
    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
    byte_size INTEGER NOT NULL,
    stored_rel_path TEXT NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE INDEX idx_attachments_note ON attachments(note_id);
