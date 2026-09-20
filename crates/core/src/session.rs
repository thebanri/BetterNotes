use crate::{
    Error, Note, NoteStore, NoteSummary, Result, SearchResult, ThemePreference, WindowState,
};
use std::path::Path;

/// Owns the active draft; only successful writes clear the dirty flag.
pub struct NotesSession {
    store: NoteStore,
    summaries: Vec<NoteSummary>,
    current: Option<Note>,
    dirty: bool,
}

impl NotesSession {
    /// One session per sticky window; the UI permits only one editor per note.
    pub fn open_note(path: &Path, id: i64) -> Result<Self> {
        let store = NoteStore::open(path)?;
        let note = store.get(id)?;
        let snippet = note.content.chars().take(80).collect();
        Ok(Self {
            store,
            summaries: vec![NoteSummary {
                id: note.id,
                title: note.title.clone(),
                snippet,
                priority: note.priority,
                is_archived: note.is_archived,
                is_pinned: note.is_pinned,
                tags: note.tags.clone(),
            }],
            current: Some(note),
            dirty: false,
        })
    }

    pub fn open(path: &Path) -> Result<Self> {
        let store = NoteStore::open(path)?;
        let summaries = store.list()?;
        let current = summaries
            .first()
            .map(|note| store.get(note.id))
            .transpose()?;
        Ok(Self {
            store,
            summaries,
            current,
            dirty: false,
        })
    }

    pub fn summaries(&self) -> &[NoteSummary] {
        &self.summaries
    }
    pub fn current(&self) -> Option<&Note> {
        self.current.as_ref()
    }
    pub fn dirty(&self) -> bool {
        self.dirty
    }

    pub fn search(&self, query: &str) -> Result<Vec<SearchResult>> {
        self.store.search(query)
    }

    pub fn list_tags(&self) -> Result<Vec<String>> {
        self.store.list_tags()
    }

    pub fn window_state(&self) -> Result<WindowState> {
        self.store
            .window_state(self.current.as_ref().ok_or(Error::NoSelection)?.id)
    }

    pub fn save_window_state(&self, state: &WindowState) -> Result<()> {
        self.store
            .save_window_state(self.current.as_ref().ok_or(Error::NoSelection)?.id, state)
    }

    pub fn open_window_ids(&self) -> Result<Vec<i64>> {
        self.store.open_window_ids()
    }

    pub fn theme(&self) -> Result<ThemePreference> {
        self.store.theme()
    }

    pub fn set_theme(&mut self, theme: ThemePreference) -> Result<()> {
        self.store.set_theme(theme)
    }

    /// Sticky reload must never silently switch to a different note after deletion.
    pub fn reload_note(&mut self) -> Result<()> {
        let id = self.current.as_ref().ok_or(Error::NoSelection)?.id;
        let note = self.store.get(id)?;
        if let Some(summary) = self.summaries.iter_mut().find(|summary| summary.id == id) {
            summary.title.clone_from(&note.title);
            summary.snippet = note.content.chars().take(80).collect();
            summary.priority = note.priority;
            summary.is_archived = note.is_archived;
            summary.is_pinned = note.is_pinned;
            summary.tags.clone_from(&note.tags);
        }
        self.current = Some(note);
        self.dirty = false;
        Ok(())
    }

    pub fn current_index(&self) -> Option<usize> {
        let current = self.current.as_ref()?;
        self.summaries.iter().position(|note| note.id == current.id)
    }

    pub fn edit_title(&mut self, title: String) {
        if let Some(note) = &mut self.current {
            if note.title != title {
                note.title = title;
                self.dirty = true;
            }
        }
    }

    pub fn edit_content(&mut self, content: String) {
        if let Some(note) = &mut self.current {
            if note.content != content {
                note.content = content;
                self.dirty = true;
            }
        }
    }

    pub fn set_pinned(&mut self, pinned: bool) -> Result<()> {
        if let Some(note) = &mut self.current {
            note.is_pinned = pinned;
            self.dirty = true;
        }
        Ok(())
    }

    pub fn set_archived(&mut self, archived: bool) -> Result<()> {
        if let Some(note) = &mut self.current {
            note.is_archived = archived;
            self.dirty = true;
        }
        Ok(())
    }

    pub fn set_priority(&mut self, priority: i32) -> Result<()> {
        if let Some(note) = &mut self.current {
            note.priority = priority.clamp(0, 3);
            self.dirty = true;
        }
        Ok(())
    }

    pub fn set_tags(&mut self, tags: Vec<String>) -> Result<()> {
        if let Some(note) = &mut self.current {
            note.tags = tags;
            self.dirty = true;
        }
        Ok(())
    }

    pub fn save(&mut self) -> Result<()> {
        if self.dirty {
            let saved = self
                .store
                .update(self.current.as_ref().ok_or(Error::NoSelection)?)?;
            if let Some(summary) = self.summaries.iter_mut().find(|note| note.id == saved.id) {
                summary.title.clone_from(&saved.title);
                summary.snippet = saved.content.chars().take(80).collect();
                summary.priority = saved.priority;
                summary.is_archived = saved.is_archived;
                summary.is_pinned = saved.is_pinned;
                summary.tags.clone_from(&saved.tags);
            }
            self.current = Some(saved);
            self.dirty = false;
        }
        Ok(())
    }

    pub fn create(&mut self) -> Result<()> {
        self.save()?;
        let note = self.store.create()?;
        self.summaries.insert(
            0,
            NoteSummary {
                id: note.id,
                title: note.title.clone(),
                snippet: String::new(),
                priority: note.priority,
                is_archived: note.is_archived,
                is_pinned: note.is_pinned,
                tags: note.tags.clone(),
            },
        );
        self.current = Some(note);
        Ok(())
    }

    pub fn select(&mut self, index: usize) -> Result<()> {
        let id = self.summaries.get(index).ok_or(Error::InvalidSelection)?.id;
        self.save()?;
        let note = self.store.get(id)?;
        self.current = Some(note);
        Ok(())
    }

    /// Called only after UI confirmation. Deleting also discards this note's draft.
    pub fn delete_current(&mut self) -> Result<()> {
        let note = self.current.as_ref().ok_or(Error::NoSelection)?;
        self.store.delete(note)?;
        self.summaries.retain(|summary| summary.id != note.id);
        self.current = None;
        self.dirty = false;
        Ok(())
    }

    /// Explicitly discard the draft after confirmation; failures retain the draft.
    pub fn reload(&mut self) -> Result<()> {
        let summaries = self.store.list()?;
        let id = self.current.as_ref().map(|note| note.id);
        let target = summaries
            .iter()
            .find(|note| Some(note.id) == id)
            .or(summaries.first());
        let current = target.map(|note| self.store.get(note.id)).transpose()?;
        self.summaries = summaries;
        self.current = current;
        self.dirty = false;
        Ok(())
    }
}
