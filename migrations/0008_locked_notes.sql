-- A locked note's content is sealed with the master password's key (see
-- crates/core/src/vault.rs) and its search text is left empty.
ALTER TABLE notes ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0 CHECK (is_locked IN (0, 1));
