# BetterNotes

Linux-first desktop notes application — **v1.0.0 (Linux Release)**.
BetterNotes is an open-source, native, lightweight, Linux-first sticky notes and desktop workspace application built with Rust and Qt 6/QML.

Create, edit and organize notes in independent floating windows, with autosave, SQLite persistence, saved window geometry, light/dark/system themes, FTS5 full-text search, system tray, global quick capture, desktop notifications, Wayland/X11 compositor compatibility, always-on-top window pinning, one-time and recurring reminders, safe file attachments, JSON/Markdown import/export, crash-safe atomic backup & restore, unified CLI, and single-instance local IPC.

---

## Key Features

- **Native Linux Experience:** First-class Wayland and X11 support with compositor integration for KDE Plasma, GNOME, XFCE, Cinnamon, MATE, Budgie, Hyprland, and Sway.
- **Independent Sticky Windows:** Edit multiple notes simultaneously. Position, size, collapsed state, and always-on-top pins are remembered across restarts.
- **Instant Full-Text Search (FTS5):** Search through note titles and bodies instantly with keyboard navigation (`Ctrl+K`).
- **Productivity & Reminders:** Set one-time or recurring reminders (Daily, Weekly, Monthly, Yearly) with Freedesktop notification alerts.
- **Data Sovereignty & Safety:** 100% offline-first, no telemetry, no cloud dependency. Full JSON and Markdown (with YAML frontmatter) import/export.
- **Crash-Safe Backup & Recovery:** Atomic SQLite backups (`VACUUM INTO`) and safe snapshot restore.
- **Single-Instance & Unified CLI:** Run commands directly from the terminal (`betternotes new`, `list`, `search`, `show`, `archive`, `backup`, `restore`, `export`, `import`) which automatically communicate with the running GUI over a private Unix domain socket.

---

## Architecture

Rust owns application logic and persistence; QML owns presentation. A Qt-independent `betternotes-core` crate manages notes, SQLite migrations, search, reminders, attachments, and IPC. A CXX-Qt adapter exposes this state to QML:

```text
Cargo.toml              Rust workspace
crates/core/src/lib.rs  Qt-independent core
crates/core/src/store.rs SQLite persistence and migrations (v1 - v5)
crates/core/src/session.rs Draft state and save-before-navigation rules
crates/core/src/settings.rs Theme preferences and settings
crates/core/src/window_state.rs Validated per-note window state
crates/core/src/reminders.rs One-time and recurring reminders
crates/core/src/attachments.rs Safe attachment storage and isolation
crates/core/src/backup.rs Atomic backup and safe restore
crates/core/src/export_import.rs JSON and Markdown export/import
crates/core/src/ipc.rs Single-instance Unix socket server and client
crates/core/src/paths.rs Linux XDG data and runtime path resolution
app/src/main.rs         CLI command router, IPC dispatch, Qt lifecycle
app/src/notes_bridge.rs CXX-Qt bridge connecting Rust core to QML
qml/themes/Theme.qml    Design system with Light/Dark/System palettes
qml/components/         Reusable UI components (buttons, badges, command palette)
qml/windows/Main.qml   Notes library, system tray, and window ownership
qml/windows/StickyNote.qml Independent sticky note editor
qml/windows/QuickCapture.qml Floating scratchpad window
packaging/linux/        Flatpak, AppImage, and Arch PKGBUILD recipes
```

---

## Installation & Packaging

### 1. Flatpak (Recommended)
```bash
flatpak-builder --user --install --force-clean build-dir packaging/linux/flatpak/org.betternotes.BetterNotes.yaml
flatpak run org.betternotes.BetterNotes
```

### 2. AppImage
```bash
./packaging/linux/appimage/build-appimage.sh
./target/BetterNotes-x86_64.AppImage
```

### 3. Arch Linux / CachyOS (PKGBUILD)
```bash
cd packaging/linux/arch
makepkg -si
```

### 4. Build from Source
```bash
# Build release binary
cargo build --release --locked

# Run BetterNotes
./target/release/betternotes
```

---

## CLI Usage

The CLI and GUI share the same domain engine. If BetterNotes is running, CLI commands update the GUI live:

```bash
# Create a note (opens in GUI if running)
betternotes new "Configure nginx" "server { listen 80; }"

# List notes
betternotes list
betternotes list --archived

# Search notes with FTS5
betternotes search nginx

# View note details
betternotes show 1

# Archive or unarchive
betternotes archive 1
betternotes archive 1 --unarchive

# Backup & Restore
betternotes backup ~/Backups
betternotes restore ~/Backups/betternotes-backup-1789924274

# Import & Export
betternotes export notes.json
betternotes export ./markdown_notes/
betternotes import notes.json

# Platform & Compositor Diagnostics
betternotes --diagnostics
```

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Ctrl + N` | New Note |
| `Ctrl + K` or `Ctrl + Shift + P` | Command Palette |
| `Ctrl + Alt + Space` | Quick Capture Scratchpad |
| `Ctrl + S` | Save Current Note Immediately |
| `Ctrl + W` | Close Active Window (preserves note) |
| `Ctrl + Q` | Save All Notes and Quit |

---

## Development & Verification

Run the test suite and validation checks:

```bash
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --locked
```

Refer to the validation reports in `docs/`:
- [Phase 10 — Linux Release Packaging](docs/phase-10-validation.md)
- [Phase 9 — CLI and IPC](docs/phase-9-validation.md)
- [Phase 8 — Productivity](docs/phase-8-validation.md)
- [Phase 7 — Wayland / X11 Compatibility](docs/phase-7-validation.md)
- [Wayland & X11 Compatibility Guide](docs/wayland-x11-compatibility.md)
- [Release Notes v1.0.0](docs/release-v1.0.md)

---

## License

BetterNotes is open-source software licensed under the [MIT License](LICENSE).
