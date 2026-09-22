# Changelog

All notable changes to the BetterNotes project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.6] - 2026-09-22

### Fixed
- Resizing sticky notes running as desktop widgets on Wayland in the AppImage no longer jitters or snaps back to the old size: the AppImage build now ensures LayerShellQt synchronizes surface geometry under Qt 6.9, and note resizing commits explicit desired sizes to KWin.
- Prevent Qt UniqueConnection assertion failure when connecting widget resize listeners.

## [0.1.5] - 2026-09-22

### Fixed
- Dragging or resizing a note shown as a desktop widget on Wayland no longer makes it shake and smear, especially with high-rate mice: the note now follows the compositor's relative pointer motion instead of pointer positions within itself, which lag behind its own moves.

## [0.1.4] - 2026-09-22

### Added
- Sticky notes stay on screen when you **show the desktop** or minimize all windows, like desktop widgets (Settings, on by default). On Wayland they are layer-shell surfaces (KDE Plasma, Hyprland, Sway and other wlroots compositors) that BetterNotes moves and resizes itself; on X11 they use the desktop window type, or dock while pinned. GNOME on Wayland has no way to allow this, so notes stay ordinary windows there. Packages now depend on LayerShellQt; the AppImage and Flatpak bundle it.
- Reminder notifications have **Open note** and **Snooze 10 min** buttons (snooze is offered for one-time reminders), where the desktop's notification service supports buttons.
- A note's title bar shows its reminder; click it to edit.
- The interface is available in **Turkish** as well as English, following the desktop's language or chosen in Settings; switching needs no restart. Qt's own dialog buttons follow when the system has Qt's translations. Some error messages from the core are still English.
- **Locked notes**: lock a note with one master password (from its ⋯ menu or its card). Its text is encrypted (XChaCha20-Poly1305 with an Argon2id-derived key) and left out of search and previews; it opens only after the password is entered, and **Lock Now** in Settings closes it again. Titles, attached files and images are not encrypted, and a forgotten password cannot be recovered. Exports and backups keep locked text encrypted.
- Two more themes, **Sepia** (warm paper) and **Black** (pure black for OLED screens), and a choice of accent colour. Theme and accent changes reach open notes at once.
- Keyboard shortcuts can be changed in Settings: click one, press the new keys. Shortcuts that clash within the library or within a note are refused, and **Reset All** restores the defaults. Tooltips show the current keys.
- Automatic backups, on by default: daily or weekly, keeping the newest 7 (1–100), in a folder of your choice. Settings also offer **Back Up Now** and show when the last backup was made.
- **Arrange notes** (sidebar, command palette, tray) lines the open notes up on the library's screen. X11 and KDE Plasma (Wayland) move them; other Wayland desktops do not let apps place windows, so the notes are only brought on screen there.
- Open text, Markdown and image files with BetterNotes from a file manager's **Open with**, or `betternotes --open FILE...`: each becomes a new note. A running BetterNotes receives them.
- A **Trash**: deleting a note moves it there, where it can be restored for 30 days before it is deleted for good (with its attached files). Trashed notes stay out of search, reminders, exports and restored windows. Emptying the trash or deleting a note for good asks first.
- Select several notes in the library (Ctrl+click, Shift+click for a range, Ctrl+A, or **Select** in a card's menu) to pin, archive, tag, move to the trash, restore or delete them together. Esc clears the selection.
- Export asks where to save (a JSON file, or a folder for Markdown), and **Import notes** in the command palette adds notes from JSON exports or Markdown files.
- The library remembers recent searches and offers them in the empty search field.
- Search results highlight where the searched words appear.
- Checklists: type `[ ] ` (or `[x] `) at a line start, or use the toolbar button (Ctrl+Shift+9); click a box or press Ctrl+Enter to tick it.
- Tab and Shift+Tab move list and checklist items a level in or out, making sub-items (also in the ⋯ menu); bullets and numbers change style per level, and Enter on an empty sub-item moves it back up a level.
- Find and replace in a note (Ctrl+F / Ctrl+H) with match counts, match case, replace and replace all.
- A **⋯** toolbar menu with paragraph alignment (left, center, right, justify; also Ctrl+Shift+L/E/R/J), find and replace, and the note's word and character count (or the selection's).
- Paste images with Ctrl+V: a screenshot or copied picture, or image files copied in a file manager.
- **Copy Image** in an image's right-click menu puts the picture on the clipboard, ready to paste into other apps.
- Right-click an image to align it or view it full size; double-clicking an image also opens it full size, with GIFs playing.
- Code blocks have a copy button.
- Attach any file to a note (the paperclip in the note toolbar, **⋯ → Attach File…**, or drop it on the note). Attached files show under the text; double-click to open, or save or remove them from their menu. Programs, scripts and launchers are never opened from a note, only saved, and attachments are stored without execute permission.
- Code blocks: type ``` (optionally with a language name) at the start of a line and press Enter to start one; Enter continues it and ``` on a line of its own ends it. A toolbar button turns selected lines into code and back. Code is monospace in a grey box and survives saving and reopening.

### Fixed
- A code block started under an image, or made with the code button over a selection that includes an image, no longer takes the image along: images now sit in a paragraph of their own, and images in older notes are separated when the note opens.
- Checklist items have proper checkboxes that are easy to click, and ticked items are struck through.
- Turning a ticked checklist item into code removes its checkbox and strike-through.
- Selecting everything and deleting it no longer leaves an empty bullet, checkbox or code block behind.
- Search matches the text of notes instead of their HTML: searching for words like "indent" no longer finds every formatted note, and result previews no longer show markup such as `text-indent:0px;">`. Existing notes are reindexed on first start.
- Export no longer writes into the directory BetterNotes was started from.
- Backups are written under a temporary name and renamed when complete, so an interrupted backup never looks finished, and a backup folder whose path contains a quote no longer breaks the backup.
- The search field and other text fields show their placeholder hint; the library search box read as empty before.
- The tag field's hint is no longer cut off.
- English texts with a count read naturally ("1 day", "2 days") instead of "day(s)".

## [0.1.3] - 2026-09-21

### Added
- Reminders for every note: the bell in a note's title bar sets, changes or removes its reminder, with a date, a time, one-click choices and daily, weekly or monthly repeats.
- Bulleted and numbered list buttons in the note toolbar (Ctrl+Shift+8 / Ctrl+Shift+7) turn the selected lines, or the caret's line, into a list and back; typing `- ` or `1. ` still works too.
- The library shows each reminder on its note card; clicking it (or the card's bell or menu) edits it there, and a new **Reminders** section lists every note that has one.

### Fixed
- A recurring reminder missed while BetterNotes was closed now fires once and moves to its next occurrence, instead of firing again every 30 seconds until it caught up.
- Palette and 1-bit images, including many GIF frames, are drawn in their colours instead of black.
- Starting an empty note with a list no longer draws the "Write your note…" hint over the first bullet.
- The **Default** note font is the desktop's font; it had fallen back to a monospace font.
- After `betternotes install` (and the curl installer) the applications menu shows the BetterNotes icon right away. Installing and uninstalling now tell the desktop that icons and menu entries changed; KDE Plasma had kept showing a blank icon from its cache.
- Desktop notifications show the BetterNotes icon, also from an AppImage or a build that is not installed, and are linked to the app's desktop entry. A note title starting with `-` is no longer read as a `notify-send` option.
- Running the test suites no longer shows notifications on the desktop.

## [0.1.2] - 2026-09-21

### Added
- `install.sh`: install or update BetterNotes with one `curl … | sh` command, verified against `SHA256SUMS`, and remove it with `--uninstall`.
- Right-clicking an image in a note offers **Save Image As…** (suggesting its original file name) and **Remove Image**.

### Fixed
- The AppImage now shows the BetterNotes icon in the Wayland taskbar instead of the generic Wayland icon. It is built with Qt 6.9, the first Qt that sends window icons to compositors supporting xdg-toplevel-icon (such as KWin).

## [0.1.1] - 2026-09-21

Published as the Latest release rather than a prerelease.

### Added
- Animated GIFs play inside notes while the note is visible.
- Images and GIFs can be dragged from a file manager onto a note.
- Clicking an image selects it; dragging its corner handle resizes it, keeping its aspect ratio.
- Typing `- `, `* `, `. ` or `1. ` at the start of a line starts a bulleted or numbered list; Enter on an empty item ends it.
- Tags are shown as removable chips; Enter or a comma adds the typed tag and Backspace in the empty field removes the last one.
- `betternotes install` / `betternotes uninstall` and a settings switch add BetterNotes to the user's applications menu with its icon, without root.

### Changed
- The image picker opens in the Pictures folder, accepts several files at once and inserts images no wider than the note, without scaling small ones up.
- Windows and the system tray use the bundled application icon, so it shows before the app is installed; packages also install PNG icon sizes.
- Icons are drawn at their real size, and the maximise/restore buttons use pixel-aligned glyphs.

### Fixed
- Image files whose path contains spaces or non-ASCII characters can be attached.
- The system tray icon no longer disappears on icon themes without `accessories-notes`.
- Note images and GIF frames are found on Qt 6.8, which looked them up under a different name and warned "Cannot read resource".

## [0.1.0] - 2026-09-21

First Linux preview. The phase history below records the work included in this
release; it does not imply v1.0 readiness on every desktop.

### Release preparation
- Gate publication on version validation, shared CI checks and package validation.
- Publish release notes, a source archive and SHA-256 checksums alongside all five Linux package formats.
- Mark 0.x releases as previews and document tag-based publication.
- Rewrite installation and build instructions with package and desktop limitations.
- Remove the separate `docs/` directory; keep setup instructions in the README and package recipes.

### Phase 10 — Linux Release Packaging
- Added Flatpak packaging manifest (`org.betternotes.BetterNotes.yaml`) targeting the KDE Qt 6 runtime.
- Added AppImage packaging builder script and `AppRun` environment launcher.
- Added Arch Linux `PKGBUILD`.
- Added standard Freedesktop desktop entry (`org.betternotes.BetterNotes.desktop`) and AppStream metadata (`org.betternotes.BetterNotes.metainfo.xml`).
- Added scalable SVG application vector icon.
- Added GitHub Actions CI/CD workflows for automated build, format, clippy lint, and tests.
- Added `LICENSE` (MIT), `CONTRIBUTING.md`, `SECURITY.md`, and complete release documentation.

### Phase 9 — CLI and Local IPC
- Implemented single-instance application coordination via private Unix domain socket (`$XDG_RUNTIME_DIR/betternotes/ipc.sock`).
- Implemented full CLI subcommands sharing the core Rust engine without logic duplication:
  - `betternotes new <TITLE> [CONTENT]`
  - `betternotes list [-a, --archived]`
  - `betternotes search <QUERY>`
  - `betternotes show <ID>`
  - `betternotes archive <ID> [--unarchive]`
- Added live action dispatch to running GUI instance (window focus, Quick Capture scratchpad activation, note opening).
- Added untrusted input validation, message size caps (1 MiB), and stale socket recovery.

### Phase 8 — Productivity
- Added reminders system with one-time and recurring intervals (`Daily`, `Weekly`, `Monthly`, `Yearly`).
- Added safe attachments manager with path traversal protection, MIME type detection, and isolated storage.
- Added JSON and Markdown (with frontmatter) import/export commands and bridge methods.
- Added crash-safe atomic backup via SQLite `VACUUM INTO` and safe snapshot restore.

### Phase 7 — Wayland / X11 Compositor Compatibility
- Added environment detection across KDE Plasma, GNOME, XFCE, Cinnamon, MATE, Budgie, Hyprland, and Sway.
- Implemented tiling window manager floating rules for Hyprland and Sway.
- Added Always-on-Top sticky note window pinning via `Qt.WindowStaysOnTopHint`.
- Added desktop diagnostic report (`betternotes --diagnostics`).

### Phase 6 — Linux Desktop Integration
- Added XDG autostart configuration (`~/.config/autostart/betternotes.desktop`).
- Added Freedesktop desktop notifications via DBus.
- Added System Tray integration with context menu actions.
- Added floating Quick Capture scratchpad (`Ctrl+Alt+Space`).
- Added native clipboard copy/paste bridge.

### Phase 5 — Search and Organization
- Added SQLite FTS5 full-text search indexing across titles and contents.
- Added note tagging with autocomplete and filtering.
- Added priority levels (`Low`, `Normal`, `High`, `Urgent`).
- Added Command Palette (`Ctrl+K`) for quick keyboard navigation.

### Phase 4 — Modern UI
- Implemented design system with Light, Dark, and System theme palettes.
- Added responsive layouts, polished badges, buttons, cards, and subtle micro-interactions.
- Added high-DPI scaling support.

### Phase 3 — Sticky Windows
- Implemented independent, simultaneous floating note windows.
- Added window state persistence (position, size, collapsed state).
- Added lost display recovery on multi-monitor setup changes.

### Phase 2 — Basic Notes
- Implemented SQLite persistence with WAL mode and versioned migrations.
- Added note CRUD operations and non-blocking autosave with revision conflict safety.

### Phase 1 — Foundation
- Initialized Rust workspace with `betternotes-core` and Qt 6 CXX-Qt bridge.
- Configured QML engine loading and Linux build system.
