# Changelog

All notable changes to the BetterNotes project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.3] - 2026-09-21

### Fixed
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
