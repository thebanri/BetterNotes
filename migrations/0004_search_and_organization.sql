ALTER TABLE notes ADD COLUMN priority INTEGER NOT NULL DEFAULT 0 CHECK (priority BETWEEN 0 AND 3);
ALTER TABLE notes ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1));
ALTER TABLE notes ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1));

CREATE TABLE tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE CHECK (length(name) > 0 AND length(name) <= 64)
);

CREATE TABLE note_tags (
    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (note_id, tag_id)
);

CREATE VIRTUAL TABLE notes_fts USING fts5(
    title,
    content,
    tags,
    tokenize="unicode61"
);

CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
    INSERT INTO notes_fts(rowid, title, content, tags) VALUES (new.id, new.title, new.content, '');
END;

CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
    DELETE FROM notes_fts WHERE rowid = old.id;
END;

CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
    UPDATE notes_fts SET title = new.title, content = new.content,
      tags = COALESCE((SELECT group_concat(t.name, ' ') FROM note_tags nt JOIN tags t ON nt.tag_id = t.id WHERE nt.note_id = new.id), '')
    WHERE rowid = new.id;
END;

CREATE TRIGGER note_tags_ai AFTER INSERT ON note_tags BEGIN
    UPDATE notes_fts SET tags = COALESCE((SELECT group_concat(t.name, ' ') FROM note_tags nt JOIN tags t ON nt.tag_id = t.id WHERE nt.note_id = new.note_id), '')
    WHERE rowid = new.note_id;
END;

CREATE TRIGGER note_tags_ad AFTER DELETE ON note_tags BEGIN
    UPDATE notes_fts SET tags = COALESCE((SELECT group_concat(t.name, ' ') FROM note_tags nt JOIN tags t ON nt.tag_id = t.id WHERE nt.note_id = old.note_id), '')
    WHERE rowid = old.note_id;
END;

INSERT INTO notes_fts(rowid, title, content, tags)
SELECT id, title, content, '' FROM notes;
