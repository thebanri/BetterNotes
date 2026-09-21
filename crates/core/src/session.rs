use crate::{
    preview::plain_preview, Error, Note, NoteStore, NoteSummary, Result, SearchResult,
    ThemePreference, WindowState,
};
use std::path::Path;

/// Preview length for list rows, matching the store's list query.
const PREVIEW_CHARS: usize = 140;

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
        let snippet = if note.is_locked {
            String::new()
        } else {
            plain_preview(&note.content, PREVIEW_CHARS)
        };
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
                is_locked: note.is_locked,
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

    pub fn notes_stay_below(&self) -> Result<bool> {
        self.store.notes_stay_below()
    }

    pub fn set_notes_stay_below(&mut self, enabled: bool) -> Result<()> {
        self.store.set_notes_stay_below(enabled)
    }

    pub fn is_autostart_enabled(&self) -> Result<bool> {
        crate::autostart::is_autostart_enabled()
    }

    pub fn set_autostart(&mut self, enabled: bool) -> Result<()> {
        crate::autostart::set_autostart(enabled, None)
    }

    /// Sticky reload must never silently switch to a different note after deletion.
    pub fn reload_note(&mut self) -> Result<()> {
        let id = self.current.as_ref().ok_or(Error::NoSelection)?.id;
        let note = self.store.get(id)?;
        if let Some(summary) = self.summaries.iter_mut().find(|summary| summary.id == id) {
            summary.title.clone_from(&note.title);
            summary.snippet = plain_preview(&note.content, PREVIEW_CHARS);
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
                // A locked note's text never reaches the list.
                summary.snippet = if saved.is_locked {
                    String::new()
                } else {
                    plain_preview(&saved.content, PREVIEW_CHARS)
                };
                summary.is_locked = saved.is_locked;
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
                is_locked: false,
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

    /// Pins or unpins any note in the list without selecting it.
    ///
    /// Library actions read the note's latest revision immediately before
    /// writing, so they never overwrite edits another editor has saved. A note
    /// that is open in its own editor must be changed through that editor
    /// instead: this write bumps the revision, and the open editor's next save
    /// would then report a conflict.
    pub fn set_note_pinned(&mut self, id: i64, pinned: bool) -> Result<()> {
        self.change_note(id, |note| note.is_pinned = pinned)
    }

    /// Archives or restores any note in the list. See [`Self::set_note_pinned`].
    pub fn set_note_archived(&mut self, id: i64, archived: bool) -> Result<()> {
        self.change_note(id, |note| note.is_archived = archived)
    }

    /// Deletes any note in the list, at its latest revision. Called only after
    /// UI confirmation. See [`Self::set_note_pinned`] for notes open elsewhere.
    pub fn delete_note(&mut self, id: i64) -> Result<()> {
        self.save()?;
        let note = self.store.get(id)?;
        self.store.delete(&note)?;
        self.reload()
    }

    /// Moves the selected note to the trash, discarding its unsaved draft
    /// (the UI confirms first).
    pub fn trash_current(&mut self) -> Result<()> {
        let note = self.current.as_ref().ok_or(Error::NoSelection)?;
        self.store.move_to_trash(note)?;
        self.summaries.retain(|summary| summary.id != note.id);
        self.current = None;
        self.dirty = false;
        Ok(())
    }

    /// Moves any listed note to the trash. See [`Self::set_note_pinned`].
    pub fn trash_note(&mut self, id: i64) -> Result<()> {
        self.save()?;
        let note = self.store.get(id)?;
        self.store.move_to_trash(&note)?;
        self.reload()
    }

    pub fn restore_note(&mut self, id: i64) -> Result<()> {
        self.store.restore_from_trash(id)?;
        self.reload()
    }

    pub fn trash(&self) -> Result<Vec<(NoteSummary, i64)>> {
        self.store.trash()
    }

    /// Deletes trashed notes for good, with their attachment files: those
    /// deleted before `before_ms`, or every one when None. Returns how many.
    pub fn empty_trash(&mut self, before_ms: Option<i64>) -> Result<usize> {
        let ids = self.store.trashed_ids(before_ms)?;
        for &id in &ids {
            self.delete_forever(id)?;
        }
        Ok(ids.len())
    }

    /// Deletes one trashed note for good, with its attachment files.
    pub fn delete_forever(&mut self, id: i64) -> Result<()> {
        let attachments = self.list_attachments(id)?;
        self.store.delete_from_trash(id)?;
        if let Ok(data_dir) = crate::paths::data_directory(
            std::env::var_os("XDG_DATA_HOME").as_deref(),
            std::env::var_os("HOME").as_deref(),
        ) {
            for attachment in attachments {
                let _ = std::fs::remove_file(crate::stored_path(&data_dir, &attachment));
            }
        }
        Ok(())
    }

    /// Locks or unlocks the selected note's content with the master password.
    /// Both need the password unlocked: locking seals the content, unlocking
    /// stores it readable again.
    pub fn set_locked(&mut self, locked: bool) -> Result<()> {
        if !crate::vault::is_unlocked() {
            return Err(Error::Locked);
        }
        let note = self.current.as_mut().ok_or(Error::NoSelection)?;
        note.is_locked = locked;
        self.dirty = true;
        self.save()
    }

    /// Locks or unlocks any listed note. See [`Self::set_note_pinned`].
    pub fn set_note_locked(&mut self, id: i64, locked: bool) -> Result<()> {
        if !crate::vault::is_unlocked() {
            return Err(Error::Locked);
        }
        self.change_note(id, |note| note.is_locked = locked)
    }

    /// Adds a tag to any listed note. See [`Self::set_note_pinned`].
    pub fn add_note_tag(&mut self, id: i64, tag: &str) -> Result<()> {
        let tag = tag.trim().trim_start_matches('#').trim().to_string();
        if tag.is_empty() {
            return Ok(());
        }
        self.change_note(id, |note| {
            if !note
                .tags
                .iter()
                .any(|existing| existing.eq_ignore_ascii_case(&tag))
            {
                note.tags.push(tag);
            }
        })
    }

    /// The note's title and body as plain text, for copying out of the app.
    pub fn plain_text(&self, id: i64) -> Result<String> {
        let note = self.store.get(id)?;
        let body = crate::preview::to_plain_text(&note.content);
        let body = body.trim();
        Ok(match (note.title.trim(), body) {
            ("", body) => body.to_string(),
            (title, "") => title.to_string(),
            (title, body) => format!("{title}\n\n{body}"),
        })
    }

    fn change_note(&mut self, id: i64, change: impl FnOnce(&mut Note)) -> Result<()> {
        // Commit this session's own draft first so the reload below keeps it.
        self.save()?;
        let mut note = self.store.get(id)?;
        change(&mut note);
        self.store.update(&note)?;
        self.reload()
    }

    pub fn store(&self) -> &NoteStore {
        &self.store
    }

    pub fn set_reminder(
        &self,
        note_id: i64,
        remind_at: i64,
        recurrence: crate::Recurrence,
    ) -> Result<i64> {
        if remind_at <= 0 {
            return Err(Error::InvalidReminder);
        }
        crate::set_reminder(self.store.raw_connection(), note_id, remind_at, recurrence)
    }

    /// The active reminder of each listed note, in list order.
    pub fn summary_reminders(&self) -> Result<Vec<Option<(i64, crate::Recurrence)>>> {
        let mut reminders = crate::reminders::active_reminders(self.store.raw_connection())?;
        Ok(self
            .summaries
            .iter()
            .map(|note| reminders.remove(&note.id))
            .collect())
    }

    pub fn get_reminder(&self, note_id: i64) -> Result<Option<crate::Reminder>> {
        crate::get_reminder_for_note(self.store.raw_connection(), note_id)
    }

    pub fn clear_reminder(&self, note_id: i64) -> Result<()> {
        crate::clear_reminder_for_note(self.store.raw_connection(), note_id)
    }

    pub fn check_due_reminders(&self, now_sec: i64) -> Result<Vec<crate::DueReminder>> {
        crate::get_due_reminders(self.store.raw_connection(), now_sec)
    }

    pub fn dismiss_reminder(&self, reminder_id: i64, now_sec: i64) -> Result<()> {
        crate::reminders::complete_reminder(self.store.raw_connection(), reminder_id, now_sec)
    }

    pub fn add_attachment(
        &self,
        data_dir: &Path,
        note_id: i64,
        source_path: &Path,
    ) -> Result<crate::Attachment> {
        crate::add_attachment(data_dir, self.store.raw_connection(), note_id, source_path)
    }

    pub fn list_attachments(&self, note_id: i64) -> Result<Vec<crate::Attachment>> {
        crate::list_attachments(self.store.raw_connection(), note_id)
    }

    pub fn delete_attachment(&self, data_dir: &Path, attachment_id: &str) -> Result<()> {
        crate::delete_attachment(data_dir, self.store.raw_connection(), attachment_id)
    }

    pub fn export_json(&self, output_path: &Path) -> Result<()> {
        let notes = self.store.all_notes_for_export()?;
        crate::export_notes_json(&notes, output_path)
    }

    pub fn export_markdown(&self, output_dir: &Path) -> Result<()> {
        let notes = self.store.all_notes_for_export()?;
        crate::export_notes_markdown_dir(&notes, output_dir)
    }

    pub fn import_json(&mut self, input_path: &Path) -> Result<usize> {
        let count = crate::import_notes_json(&self.store, input_path)?;
        self.reload()?;
        Ok(count)
    }

    pub fn import_markdown(&mut self, input_path: &Path) -> Result<usize> {
        let count = crate::import_note_markdown_file(&self.store, input_path)?;
        self.reload()?;
        Ok(count)
    }

    /// The colour of each listed note, in list order. Notes without a chosen
    /// colour are yellow, matching [`Self::note_color`].
    pub fn summary_colors(&self) -> Result<Vec<String>> {
        let mut colors = self.store.note_colors()?;
        Ok(self
            .summaries
            .iter()
            .map(|note| {
                colors
                    .remove(&note.id)
                    .unwrap_or_else(|| "yellow".to_string())
            })
            .collect())
    }

    pub fn note_color(&self) -> String {
        if let Some(note) = &self.current {
            self.store
                .get_setting(&format!("note_color_{}", note.id))
                .ok()
                .flatten()
                .unwrap_or_else(|| "yellow".to_string())
        } else {
            "yellow".to_string()
        }
    }

    pub fn set_note_color(&self, color: &str) -> Result<()> {
        if let Some(note) = &self.current {
            self.store
                .set_setting(&format!("note_color_{}", note.id), color)
        } else {
            Ok(())
        }
    }

    pub fn note_font_family(&self) -> String {
        if let Some(note) = &self.current {
            self.store
                .get_setting(&format!("note_font_family_{}", note.id))
                .ok()
                .flatten()
                .unwrap_or_else(|| "default".to_string())
        } else {
            "default".to_string()
        }
    }

    pub fn set_note_font_family(&self, font_family: &str) -> Result<()> {
        if let Some(note) = &self.current {
            self.store
                .set_setting(&format!("note_font_family_{}", note.id), font_family)
        } else {
            Ok(())
        }
    }

    pub fn note_font_size(&self) -> i32 {
        if let Some(note) = &self.current {
            self.store
                .get_setting(&format!("note_font_size_{}", note.id))
                .ok()
                .flatten()
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(13)
        } else {
            13
        }
    }

    pub fn set_note_font_size(&self, font_size: i32) -> Result<()> {
        if let Some(note) = &self.current {
            self.store.set_setting(
                &format!("note_font_size_{}", note.id),
                &font_size.to_string(),
            )
        } else {
            Ok(())
        }
    }

    pub fn add_attachment_file(&self, source_path: &Path) -> Result<crate::Attachment> {
        let note = self.current.as_ref().ok_or(Error::NoSelection)?;
        let data_dir = crate::paths::data_directory(
            std::env::var_os("XDG_DATA_HOME").as_deref(),
            std::env::var_os("HOME").as_deref(),
        )?;
        self.add_attachment(&data_dir, note.id, source_path)
    }
}
