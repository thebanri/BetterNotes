//! Keyboard shortcuts the user can change: each action's default, its
//! scope (the library window or a note window), and the saved choices.

use crate::{Error, NoteStore, Result};
use std::collections::BTreeMap;

const SETTING_KEY: &str = "shortcuts";
/// Longest key sequence accepted, as text ("Ctrl+Alt+Shift+PgDown").
const MAX_SEQUENCE_LENGTH: usize = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    Library,
    Note,
}

#[derive(Debug, Clone, Copy)]
pub struct Binding {
    pub action: &'static str,
    pub scope: Scope,
    pub default: &'static str,
}

const fn bind(action: &'static str, scope: Scope, default: &'static str) -> Binding {
    Binding {
        action,
        scope,
        default,
    }
}

/// Every configurable shortcut, in the order settings list them.
pub const BINDINGS: &[Binding] = &[
    bind("new_note", Scope::Library, "Ctrl+N"),
    bind("focus_search", Scope::Library, "Ctrl+F"),
    bind("command_palette", Scope::Library, "Ctrl+K"),
    bind("quick_capture", Scope::Library, "Ctrl+Alt+Space"),
    bind("bold", Scope::Note, "Ctrl+B"),
    bind("italic", Scope::Note, "Ctrl+I"),
    bind("underline", Scope::Note, "Ctrl+U"),
    bind("heading1", Scope::Note, "Ctrl+1"),
    bind("heading2", Scope::Note, "Ctrl+2"),
    bind("bullet_list", Scope::Note, "Ctrl+Shift+8"),
    bind("numbered_list", Scope::Note, "Ctrl+Shift+7"),
    bind("checklist", Scope::Note, "Ctrl+Shift+9"),
    bind("toggle_check", Scope::Note, "Ctrl+Return"),
    bind("find", Scope::Note, "Ctrl+F"),
    bind("replace", Scope::Note, "Ctrl+H"),
    bind("align_left", Scope::Note, "Ctrl+Shift+L"),
    bind("align_center", Scope::Note, "Ctrl+Shift+E"),
    bind("align_right", Scope::Note, "Ctrl+Shift+R"),
    bind("align_justify", Scope::Note, "Ctrl+Shift+J"),
];

fn binding(action: &str) -> Option<&'static Binding> {
    BINDINGS.iter().find(|binding| binding.action == action)
}

fn saved(store: &NoteStore) -> Result<BTreeMap<String, String>> {
    let text = store.get_setting(SETTING_KEY)?.unwrap_or_default();
    if text.trim().is_empty() {
        return Ok(BTreeMap::new());
    }
    // A damaged value is ignored rather than breaking every shortcut.
    Ok(serde_json::from_str(&text).unwrap_or_default())
}

/// Every action's shortcut: the user's choice, or the default.
pub fn load(store: &NoteStore) -> Result<BTreeMap<String, String>> {
    let saved = saved(store)?;
    Ok(BINDINGS
        .iter()
        .map(|binding| {
            let sequence = saved
                .get(binding.action)
                .cloned()
                .unwrap_or_else(|| binding.default.to_string());
            (binding.action.to_string(), sequence)
        })
        .collect())
}

/// Sets one action's shortcut. Refuses an unknown action, an empty or
/// overlong sequence, and one another action in the same window already uses.
pub fn set(store: &NoteStore, action: &str, sequence: &str) -> Result<()> {
    let invalid = |message: String| {
        Err(Error::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            message,
        )))
    };
    let Some(target) = binding(action) else {
        return invalid(format!("Unknown shortcut action: {action}"));
    };
    let sequence = sequence.trim();
    if sequence.is_empty() || sequence.len() > MAX_SEQUENCE_LENGTH {
        return invalid("Press a key combination for the shortcut".into());
    }
    let current = load(store)?;
    if let Some(other) = BINDINGS.iter().find(|other| {
        other.action != action
            && other.scope == target.scope
            && current[other.action].eq_ignore_ascii_case(sequence)
    }) {
        return invalid(format!("{sequence} is already used by {}", other.action));
    }
    let mut saved = saved(store)?;
    if sequence.eq_ignore_ascii_case(target.default) {
        saved.remove(action);
    } else {
        saved.insert(action.to_string(), sequence.to_string());
    }
    store.set_setting(
        SETTING_KEY,
        &serde_json::to_string(&saved).map_err(|e| Error::Serialization(e.to_string()))?,
    )
}

/// Returns every shortcut to its default.
pub fn reset(store: &NoteStore) -> Result<()> {
    store.set_setting(SETTING_KEY, "")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_changes_conflicts_and_reset() {
        let dir = tempfile::tempdir().unwrap();
        let store = NoteStore::open(&dir.path().join("notes.sqlite3")).unwrap();
        let keys = load(&store).unwrap();
        assert_eq!(keys.len(), BINDINGS.len());
        assert_eq!(keys["bold"], "Ctrl+B");

        set(&store, "bold", "Ctrl+Shift+B").unwrap();
        assert_eq!(load(&store).unwrap()["bold"], "Ctrl+Shift+B");
        // Taken in the same window.
        assert!(set(&store, "italic", "ctrl+shift+b").is_err());
        assert!(set(&store, "find", "Ctrl+Shift+E").is_err());
        // The library and a note are different windows.
        set(&store, "new_note", "Ctrl+Shift+B").unwrap();
        assert!(set(&store, "unknown", "Ctrl+Q").is_err());
        assert!(set(&store, "bold", " ").is_err());

        // Choosing the default again stores nothing for it.
        set(&store, "bold", "Ctrl+B").unwrap();
        assert!(!store
            .get_setting(SETTING_KEY)
            .unwrap()
            .unwrap()
            .contains("bold"));

        reset(&store).unwrap();
        assert_eq!(load(&store).unwrap()["new_note"], "Ctrl+N");

        store.set_setting(SETTING_KEY, "{not json").unwrap();
        assert_eq!(load(&store).unwrap()["bold"], "Ctrl+B");
    }

    #[test]
    fn defaults_do_not_conflict() {
        for scope in [Scope::Library, Scope::Note] {
            let mut seen = std::collections::HashSet::new();
            for binding in BINDINGS.iter().filter(|binding| binding.scope == scope) {
                assert!(
                    seen.insert(binding.default.to_lowercase()),
                    "{}",
                    binding.default
                );
            }
        }
    }
}
