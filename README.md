# BetterNotes

[![CI](https://github.com/thebanri/BetterNotes/actions/workflows/ci.yml/badge.svg)](https://github.com/thebanri/BetterNotes/actions/workflows/ci.yml)
[![Packages](https://github.com/thebanri/BetterNotes/actions/workflows/packages.yml/badge.svg)](https://github.com/thebanri/BetterNotes/actions/workflows/packages.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Sticky notes for the Linux desktop, built with **Rust and Qt 6/QML**.
Keep notes in independent windows, search your library, and capture ideas without
an account or a cloud service. Notes stay on your machine.

**[Download releases](https://github.com/thebanri/BetterNotes/releases)** ·
[Build from source](#build-from-source) · [Contribute](CONTRIBUTING.md)

> BetterNotes is a working project name. The current version is **0.1.4**, a
> Linux preview; desktop compatibility still needs testing across environments.
> Windows and macOS are not current release targets.

## Features

- Independent sticky windows with autosave, resizing, collapse and saved window state.
- Rich text editing, automatic bulleted and numbered lists, checklists, links, colors, and light, dark or system themes.
- Images and animated GIFs: pick them or drop them onto a note, drag a corner to resize, right-click to save a copy.
- SQLite storage, FTS5 search, tags, priorities and archiving.
- Quick Capture, a command palette, a system tray and start-at-login settings.
- Reminders for each note (one-time or repeating), editable from the note or the library, with desktop notifications; file attachments.
- JSON/Markdown import and export, database and attachment backups, and restore.
- A CLI sharing the Rust core with the GUI, plus local single-instance IPC.
- Locked notes: encrypt a note's text with a master password (see below).
- English and Turkish interface.
- Offline use without accounts, telemetry or a remote server.

Desktop integration depends on the session and package format; see
[Linux desktop behavior](#linux-desktop-behavior).

## Install

The quickest way, for your user only and without root, installs the latest
AppImage with its menu entry and icon, and checks it against `SHA256SUMS`:

```bash
curl -fsSL https://raw.githubusercontent.com/thebanri/BetterNotes/main/install.sh | sh
```

Run the same command again to update. To remove it (your notes are kept):

```bash
curl -fsSL https://raw.githubusercontent.com/thebanri/BetterNotes/main/install.sh | sh -s -- --uninstall
```

To use your distribution's package manager instead, open **[GitHub Releases](https://github.com/thebanri/BetterNotes/releases)** and
expand **Assets** on the **Latest** release. Packages are currently built for
**x86_64 / amd64**.

| Format | Target | Install the downloaded file |
| --- | --- | --- |
| `.deb` | Debian 13; Ubuntu compatibility checked on the rolling image | `sudo apt install ./betternotes_<version>_amd64.deb` |
| `.rpm` | Fedora; built and checked on the current Fedora image | `sudo dnf install ./betternotes-<version>-1.fc<release>.x86_64.rpm` |
| `.pkg.tar.zst` | Arch Linux; check dependency versions on derivatives | `sudo pacman -U ./betternotes-<version>-1-x86_64.pkg.tar.zst` |
| `.AppImage` | Linux with glibc 2.35+ and compatible desktop libraries | Make executable and run; see below |
| `.flatpak` | Distributions with Flatpak and the KDE runtime | Install the bundle; see below |

Replace placeholders with the actual asset filename. Native packages use system
Qt and their package manager installs dependencies. The AppImage bundles Qt;
Flatpak uses the KDE runtime. The AppImage is built on Ubuntu 22.04 and smoke-tested
on Ubuntu 24.04. These checks do not certify every distribution or desktop session.

### AppImage

For the current preview:

```bash
chmod +x BetterNotes-0.1.4-x86_64.AppImage
./BetterNotes-0.1.4-x86_64.AppImage
```

If FUSE is unavailable, run with extraction enabled:

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./BetterNotes-0.1.4-x86_64.AppImage
```

### Flatpak

Add Flathub as a source for the KDE runtime, then install the downloaded bundle:

```bash
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./BetterNotes-0.1.4-x86_64.flatpak
flatpak run org.betternotes.BetterNotes
```

BetterNotes itself is **not published on Flathub**. The bundle has additional
[KDE integration and autostart limitations](packaging/linux/README.md#desktop-integration-per-format).

### Add a downloaded build to the applications menu

A build from source or an AppImage has no menu entry of its own. Run it once with
`install` (or turn on **Show in applications menu** in the settings) to add one
for your user, with its icon; no root is needed:

```bash
./target/release/betternotes install      # copies the binary to ~/.local/bin
./BetterNotes-0.1.4-x86_64.AppImage install   # launches the AppImage where it is
betternotes uninstall                     # removes the entry, icons and copied binary; notes stay
```

The entry goes to `$XDG_DATA_HOME/applications` and the icons to
`$XDG_DATA_HOME/icons/hicolor`. On Wayland, desktops that do not support the
xdg-toplevel-icon protocol show the window icon only once this entry exists.
Package and Flatpak installs already have one.

### Verify a download

Download `SHA256SUMS` from the same release into the directory containing your
package, then run:

```bash
sha256sum --check --ignore-missing SHA256SUMS
```

Your package must appear with `OK`. Checksums detect damaged or mismatched downloads;
these packages are not independently signed.

For builds between releases, successful
[Packages runs](https://github.com/thebanri/BetterNotes/actions/workflows/packages.yml)
provide build artifacts (GitHub sign-in required), or you can build locally.

## Linux desktop behavior

Wayland and X11 are both targets. Positioning, stacking, focus and tray availability
vary between desktops; headless CI tests verify startup, not compositor behavior.

- **X11:** saved positions are restored and Qt window hints are used.
- **Wayland:** the compositor generally controls placement and activation.
  KDE Plasma has optional KWin integration for note placement and layering;
  this requires host tools that are unavailable in the Flatpak sandbox.
- **Show desktop / minimize all:** sticky notes stay on screen like desktop
  widgets (Settings → *Keep notes visible when showing the desktop*, on by
  default). On Wayland this uses the wlr-layer-shell protocol through
  LayerShellQt: KDE Plasma, Hyprland, Sway and other wlroots compositors.
  There notes are moved and resized by BetterNotes itself, stay out of the
  taskbar and window switcher, and a note keeps to one monitor while being
  dragged, jumping to the monitor under it when released. On X11 notes get the
  desktop window type (dock while pinned); this is untested on XFCE,
  Cinnamon and MATE, where desktop icons may cover unpinned notes. **GNOME on
  Wayland** offers no way for an app to keep windows on screen through
  "show desktop", so there notes stay ordinary windows. Builds without
  LayerShellQt (see *Build from source*) leave notes as ordinary windows on
  Wayland too.
- **System tray:** requires a tray host. The library window remains available
  when the session has none.
- **Global Quick Capture:** bind `betternotes --quick-capture` in your desktop's
  shortcut settings. The in-app shortcut does not register a desktop-wide hotkey.
- **Reminders:** require BetterNotes to remain running; notification delivery
  depends on the desktop notification service.

Use `betternotes --diagnostics` when reporting desktop integration issues.

## Locked notes

Lock a note from its **⋯** menu or its card's menu. The first time, you choose
a master password; every locked note uses it. A locked note's text is encrypted
with XChaCha20-Poly1305 under a key derived from the password with Argon2id, is
left out of search and previews, and opens only after you enter the password.
The key stays in memory until **Lock Now** (Settings) or quitting.

- The password is not stored and **cannot be recovered**. Without it, locked
  notes cannot be opened.
- Titles, attached files and images are **not** encrypted.
- Exports and backups keep locked text encrypted; importing it needs the same
  password.

## Keyboard shortcuts

| Shortcut | Action / scope |
| --- | --- |
| `Ctrl+N` | New note in the library |
| `Ctrl+F` | Focus library search |
| `Ctrl+K` / `Ctrl+Shift+P` | Open the library command palette |
| `Ctrl+Alt+Space` | Quick Capture while the library is active |
| `Ctrl+S` | Save the active sticky note immediately |
| `Ctrl+W` | Close the active sticky window, preserving its note |
| `Ctrl+Q` | Save and quit |
| `Ctrl+B` / `Ctrl+I` / `Ctrl+U` | Bold / italic / underline in the editor |

## CLI and local data

```bash
betternotes new "Configure nginx" "Check the server configuration"
betternotes list
betternotes search nginx
betternotes show 1
betternotes archive 1
betternotes archive 1 --unarchive
betternotes --quick-capture
betternotes export notes.json
betternotes export ./markdown-notes/
betternotes import notes.json
betternotes backup ~/Backups
betternotes restore /path/to/betternotes-backup-directory
betternotes install
betternotes uninstall
betternotes --help
```

Notes are stored in `$XDG_DATA_HOME/betternotes/notes.sqlite3`, falling back to
`~/.local/share/betternotes/notes.sqlite3`. Attachments live alongside the database.
Flatpak uses its own sandbox data directory. Back up before switching builds or
restoring older data.

## Build from source

Use a current stable Rust toolchain, a C++17 compiler, `pkg-config`, SQLite
headers, and **Qt 6.5+** with Qt Quick, QML, Quick Controls and the appropriate
Wayland/X11 plugins. GUI tests additionally need **Qt 6.7+** and the QtTest QML
module. Cargo invokes CXX-Qt and Qt build tools; no separate CMake invocation is
needed.

On Arch Linux / CachyOS:

```bash
sudo pacman -S --needed base-devel rust pkgconf sqlite qt6-base qt6-declarative qt6-wayland layer-shell-qt
```

Desktop widgets (notes that stay through "show desktop") are optional at
build time: they need LayerShellQt built for the same Qt (Wayland) and Qt's
private QtGui headers (X11). The build uses whichever it finds next to Qt, and
`BETTERNOTES_LAYER_SHELL_PREFIX` points it at LayerShellQt elsewhere;
[packaging/linux/build-layer-shell-qt.sh](packaging/linux/build-layer-shell-qt.sh)
builds one for a Qt that lacks it. `BETTERNOTES_NO_DESKTOP_WIDGETS=1` leaves
both out.

For Debian 13, use the complete development and QML dependency list in
[CI](.github/workflows/ci.yml). Fedora dependencies are listed in the
[RPM recipe](packaging/linux/rpm/betternotes.spec). Distribution Qt packages older
than 6.5 need a newer Qt installation to build the app.

```bash
git clone https://github.com/thebanri/BetterNotes.git
cd BetterNotes
cargo build --release --locked
./target/release/betternotes
```

Set `QMAKE=/path/to/qt6/bin/qmake` if Qt is not discovered automatically.
To create distributable packages, follow the [packaging guide](packaging/linux/README.md).

## Development

Rust owns application logic, data and platform services. QML owns presentation
and interaction. `crates/core` is Qt-independent; `app` provides the CXX-Qt bridge;
`qml` contains windows, components and themes.

```bash
cargo fmt --check
cargo check --locked
cargo clippy --all-targets --all-features --locked -- -D warnings
cargo test --locked
cargo build --release --locked
```

See [contributing](CONTRIBUTING.md), [packaging](packaging/linux/README.md)
and [security reporting](SECURITY.md).

## License

[MIT](LICENSE).
