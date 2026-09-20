use crate::{Error, Note, NoteStore, NoteSummary, Result, WindowState};
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
        Ok(Self {
            store,
            summaries: vec![NoteSummary {
                id: note.id,
                title: note.title.clone(),
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

    /// Sticky reload must never silently switch to a different note after deletion.
    pub fn reload_note(&mut self) -> Result<()> {
        let id = self.current.as_ref().ok_or(Error::NoSelection)?.id;
        let note = self.store.get(id)?;
        if let Some(summary) = self.summaries.iter_mut().find(|summary| summary.id == id) {
            summary.title.clone_from(&note.title);
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

    pub fn save(&mut self) -> Result<()> {
        if self.dirty {
            let saved = self
                .store
                .update(self.current.as_ref().ok_or(Error::NoSelection)?)?;
            if let Some(summary) = self.summaries.iter_mut().find(|note| note.id == saved.id) {
                summary.title.clone_from(&saved.title);
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
