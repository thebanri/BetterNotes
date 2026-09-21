-- Search the text people wrote, not the HTML that stores its formatting.
-- search_text holds each note's plain text, written by the application on
-- every save; SQLite cannot strip HTML itself. The full-text index now reads
-- it instead of content, so matches and snippets never show markup.
ALTER TABLE notes ADD COLUMN search_text TEXT NOT NULL DEFAULT '';

DROP TRIGGER notes_ai;
DROP TRIGGER notes_au;

CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
    INSERT INTO notes_fts(rowid, title, content, tags) VALUES (new.id, new.title, new.search_text, '');
END;

CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
    UPDATE notes_fts SET title = new.title, content = new.search_text,
      tags = COALESCE((SELECT group_concat(t.name, ' ') FROM note_tags nt JOIN tags t ON nt.tag_id = t.id WHERE nt.note_id = new.id), '')
    WHERE rowid = new.id;
END;
