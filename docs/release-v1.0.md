# BetterNotes v1.0.0 — Linux Release Guide

BetterNotes is a production-quality, open-source, Linux-first sticky notes and desktop workspace application.

## System Architecture

BetterNotes maintains a strict separation of concerns:
- **Rust Core (`betternotes-core`):** Application domain logic, SQLite storage, schema migrations, full-text search (FTS5), reminders scheduling, attachments management, import/export, atomic backup/restore, Freedesktop notifications, and single-instance Unix domain socket IPC.
- **Qt 6 QML Layer:** Modern, hardware-accelerated declarative UI, responsive themes (Light, Dark, System), keyboard shortcuts, command palette, and multi-monitor window management.

## Installation & Packaging Options

### 1. Flatpak (Recommended)

Flatpak provides an isolated, sandboxed environment compatible with all modern Linux distributions.

```bash
# Build and install locally
flatpak-builder --user --install --force-clean build-dir packaging/linux/flatpak/org.betternotes.BetterNotes.yaml

# Launch application
flatpak run org.betternotes.BetterNotes
```

### 2. AppImage

The AppImage package is a standalone portable binary requiring no root privileges or package manager installation:

```bash
./packaging/linux/appimage/build-appimage.sh
./target/BetterNotes-x86_64.AppImage
```

### 3. Arch Linux (PKGBUILD)

Arch Linux and CachyOS users can build and install via `makepkg`:

```bash
cd packaging/linux/arch
makepkg -si
```

### 4. Build from Source

```bash
# Install system build dependencies (Qt 6, SQLite 3, Rust 1.88+)
cargo build --release --locked

# Binary is available at target/release/betternotes
./target/release/betternotes
```

---

## Desktop Environment & Compositor Support

BetterNotes is tested and supported on both Wayland and X11:

| Desktop Environment | Wayland Support | X11 Support | Window Management Notes |
| :--- | :---: | :---: | :--- |
| **KDE Plasma** | :white_check_mark: | :white_check_mark: | Native window grouping, system tray, notifications, always-on-top |
| **GNOME** | :white_check_mark: | :white_check_mark: | Wayland client-side placement; tray via AppIndicator extension |
| **XFCE** | N/A | :white_check_mark: | Full X11 window placement and system tray integration |
| **Cinnamon / MATE / Budgie** | N/A | :white_check_mark: | Native X11 window control and notification daemon |
| **Hyprland** | :white_check_mark: | N/A | Tiling compositor: automatic floating rule `windowrule = float, ^(betternotes)$` |
| **Sway** | :white_check_mark: | N/A | Tiling compositor: automatic floating rule `for_window [app_id="betternotes"] floating enable` |

Run diagnostics at any time:
```bash
betternotes --diagnostics
```

---

## Command Line Interface (CLI)

BetterNotes includes a full-featured CLI sharing 100% of domain and database logic. If the GUI application is already running, CLI commands communicate live with the running instance over local IPC:

```bash
# Create a note
betternotes new "Project Ideas" "Explore WebAssembly and Rust"

# List notes
betternotes list
betternotes list --archived

# Search using SQLite FTS5
betternotes search "WebAssembly"

# Display full note content and metadata
betternotes show 1

# Archive or unarchive note
betternotes archive 1
betternotes archive 1 --unarchive

# Backup & Restore
betternotes backup ~/Backups
betternotes restore ~/Backups/betternotes-backup-1789924274

# Import & Export
betternotes export my_notes.json
betternotes export ./markdown_notes/
betternotes import notes_backup.json
betternotes import note.md
```

---

## Default Keyboard Shortcuts

| Shortcut | Action | Scope |
| :--- | :--- | :--- |
| `Ctrl + N` | New Note | Main Window |
| `Ctrl + K` or `Ctrl + Shift + P` | Command Palette | Global within App |
| `Ctrl + Alt + Space` | Quick Capture Scratchpad | Desktop / App |
| `Ctrl + S` | Force Autosave | Active Note Window |
| `Ctrl + Q` | Quit Application | Main Window |
