-- Deleting a note moves it to the trash: deleted_at is when (Unix ms), NULL
-- for notes that are not in the trash. Notes leave the trash for good when
-- the user deletes them there or after 30 days.
ALTER TABLE notes ADD COLUMN deleted_at INTEGER;
CREATE INDEX idx_notes_deleted ON notes(deleted_at);
