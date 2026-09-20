# BetterNotes

Linux-first desktop notes application, currently at **Phase 4 — Modern UI**.
BetterNotes is a working codename. Create, edit and delete plain-text notes in
independent windows, with autosave, SQLite persistence, saved window state,
and light/dark/system themes with polished QML components.

## Architecture

Rust owns application behavior; QML owns presentation. A Qt-independent
`betternotes-core` crate owns notes, SQLite migrations, persistence, draft
state and user settings. A CXX-Qt adapter exposes this state to QML, which is embedded as Qt resources.

```text
Cargo.toml              Rust workspace
crates/core/src/lib.rs  Qt-independent core
crates/core/src/store.rs SQLite persistence and migrations
crates/core/src/session.rs Draft state and save-before-navigation rules
crates/core/src/settings.rs Theme preferences and settings
crates/core/src/window_state.rs Validated per-note window state
crates/core/src/paths.rs Linux XDG data path resolution
app/build.rs            CXX-Qt code generation and Qt resources
app/src/main.rs         Qt lifecycle and startup errors
app/src/engine.rs       Shared QML loading and error handling
app/src/platform.rs     Qt platform capability policy
app/src/notes_bridge.rs Notes QObject exposed to QML
qml/themes/Theme.qml    Design system with light/dark palettes
qml/components/         Reusable UI components (buttons, badges, cards)
qml/windows/Main.qml   Notes library and window ownership
qml/windows/StickyNote.qml Independent note editor
qml/windows/WindowPlacement.js Display fitting and recovery
qml/qml.qrc            Embedded UI resource manifest
migrations/            Versioned SQL schema
docs/architecture.md   Integration evaluation and decisions
```

See [the architecture decision](docs/architecture.md) for the evaluated bindings,
ownership boundaries and future integration considerations.

## Linux development dependencies

Use current stable Rust/Cargo with rustfmt, a C++17 compiler (GCC or Clang),
linker, and Qt **6** development libraries and tools. The locked dependencies
require at least Rust 1.88; only the toolchain in the validation report has been
tested. Required Qt modules are Core, Gui, Qml, Quick, Quick Controls and Layouts.
Qt tools include `qmake6`, `moc`, `rcc` and `qmltyperegistrar`. Install Qt's QML
runtime imports and the platform plugins for your session as well as headers.
SQLite 3.34.1 or newer, its development headers, and pkg-config are also required.
`rusqlite` links the system SQLite library; it does not download or compile a
bundled copy.

On Arch Linux / CachyOS:

```sh
sudo pacman -S --needed base-devel rust sqlite pkgconf qt6-base qt6-declarative qt6-wayland
```

If using rustup instead of distribution Rust, use the stable toolchain with
`rustup component add rustfmt`. Do not install a second conflicting Rust provider.
The Qt packages include development tools and QML modules on Arch.
([Qt base package](https://archlinux.org/packages/extra/x86_64/qt6-base/),
[Qt Wayland package](https://archlinux.org/packages/extra/x86_64/qt6-wayland/))

On Ubuntu 24.04 or newer, install the system build and Qt packages, then provide
a current stable Rust toolchain (older distro Rust may be insufficient):

```sh
sudo apt install build-essential pkg-config libsqlite3-dev \
  qt6-base-dev qt6-base-dev-tools qt6-declarative-dev qt6-declarative-dev-tools \
  qmake6 qt6-qpa-plugins qt6-wayland \
  qml6-module-qtquick qml6-module-qtquick-window qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts qml6-module-qtquick-templates qml6-module-qtqml-workerscript
```

Ubuntu splits QML runtime imports into separate packages; see the
[Qt declarative package list](https://packages.ubuntu.com/source/noble/qt6-declarative).
Ubuntu and older Qt versions have not yet been validated for this project.

**CMake and Ninja are not required by this build.** Cargo's build script invokes
the compiler and Qt tools through CXX-Qt. No Qt SDK is downloaded automatically.
For a nonstandard Qt installation, set `QMAKE=/path/to/qt6/bin/qmake` when building.
The workspace requests Qt 6 through `QT_VERSION_MAJOR`.

## Build and run

From the repository root:

```sh
cargo fetch --locked
cargo fmt --check
cargo check --locked
cargo test --locked
cargo build --locked
cargo run --locked -p betternotes
```

Use **New note** (Ctrl+N in the library), or open an existing note from the list.
Each note has its own ordinary desktop window; opening the same note again
focuses its existing window where the compositor permits. Multiple notes can be
edited at once. Use the native title bar to move a window and its borders to
resize it. **Collapse/Expand** hides/shows the editor and preserves expanded size.
Tab navigates controls; Up/Down and Enter navigate/open notes in the library.

Each editor saves after 500 ms without typing. Ctrl+S saves immediately.
**Menu → Delete note** asks for confirmation and permanently removes that note.
The window's close button or Ctrl+W saves and closes just that window; its note
stays in the library. **Menu → All notes** brings the library back into view.

Closing the library, its Quit button, or Ctrl+Q in any window saves all notes and
quits. Windows still open at quit are restored on the next launch. Individually
closed windows stay closed. Normal expanded size, collapsed state and screen name
are stored; X11 also stores position. Minimized/maximized states are deliberately
restored as ordinary windows. Geometry saves are debounced for 500 ms, with an
immediate flush when closing or quitting. Closing a window does not delete a note.

Database errors appear in the affected window and on stderr. A failed save blocks
normal closure/quit and retains every pending draft. Retry with Ctrl+S or **Menu →
Save**. **Reload saved note** asks before discarding unsaved edits and does not
switch to another note if the original was deleted externally. Copy valuable
unsaved text before reloading. For an unrecoverable error, **Discard changes and
close…** provides an explicitly confirmed escape; if storage cannot be updated,
that window may reopen next time. Startup failures offer **Retry opening**;
they never replace the database or silently use volatile storage.

Notes live in `$XDG_DATA_HOME/betternotes/notes.sqlite3`, falling back to
`$HOME/.local/share/betternotes/notes.sqlite3` if XDG_DATA_HOME is unset, empty or
relative. Newly created data directories have mode 0700. The database contains
unencrypted local text. SQLite WAL and FULL synchronization protect completed
transactions; a forced kill or power loss can still lose edits since the last
successful save. Do not delete the `-wal`/`-shm` sidecar files while the application
is running. Backup/restore tooling is not implemented yet.

The executable is `target/debug/betternotes`. It can be launched from any working
directory. Qt libraries, QML modules and platform plugins must remain installed.
After fetching dependencies, `cargo build --offline --locked` needs no network.
The application itself has no network service, account or telemetry.

Qt normally selects the desktop backend. To explicitly test an available session:

```sh
QT_QPA_PLATFORM=wayland cargo run --locked -p betternotes
QT_QPA_PLATFORM=xcb cargo run --locked -p betternotes
```

These need a working Wayland compositor or X server respectively. If Qt cannot
initialize a platform plugin, it may terminate before Rust can handle the error;
inspect Qt's stderr and use `QT_DEBUG_PLUGINS=1` for diagnostic details. Do not
substitute X11 behavior for missing Wayland functionality.

### Placement and desktop limitations

Wayland leaves absolute window placement to the compositor: BetterNotes does not
save or set global x/y coordinates there. Restoring the screen and size is a
request which tiling compositors may override. Interactive native moving/resizing
continues to use the window manager. X11 position restoration is also best effort.
See [Qt's position limitations](https://doc.qt.io/qt-6/qwindow.html#position).

On restoration, missing screens fall back to the library's current display and
geometry is clamped to display bounds. **Bring here** in the library recovers an
existing or closed note onto its current display where positioning is supported;
Wayland still chooses placement. Hotplug screen-list changes trigger recovery.
Qt Quick exposes display bounds rather than per-display work areas here, so panel
overlap can still require manual movement. These are ordinary windows, without
always-on-top, desktop-layer or workspace pinning. No tray/background mode is added.

## Validation

`cargo test` checks CRUD, reopening saved data, migrations and rollback, concurrent
edits, failed writes, crash recovery, XDG paths, and window-state persistence.
A standalone Qt test runs on its process main thread and exercises the actual
QML windows: independent edits, autosave, resizing, collapse/expand, close versus
delete, restoration, lost-display recovery calculations and refusal of unsafe quit.
Tests use temporary data directories, not your real notes. Qt's expected
missing-resource warning appears during the error-path test. Headless tests do
not establish visual quality, physical keyboard interaction or compositor compatibility.

To keep a headless executable running briefly for a manual startup check:

```sh
betternotes_test_data=$(mktemp -d)
XDG_DATA_HOME="$betternotes_test_data" QT_QPA_PLATFORM=offscreen \
  QT_QUICK_BACKEND=software timeout 3s target/debug/betternotes
```

The successful startup line should appear without QML errors. Timeout status 124
means the event loop remained running until the timeout; it is not a graceful exit.
See [the Phase 5 validation report](docs/phase-5-validation.md) for commands and
actual results. Earlier reports record [Phase 4](docs/phase-4-validation.md),
[Phase 3](docs/phase-3-validation.md), [Phase 2](docs/phase-2-validation.md) and
[Phase 1](docs/validation.md).

## Scope and next phase

Phase 5 adds SQLite FTS5 full-text search with automatic synchronization, tags,
priorities, archiving, pinned notes, an instant Command Palette (`Ctrl+K`/`Ctrl+Shift+P`),
and search/filter views in the library window.

Phase 6 will implement Linux Desktop Integration: system tray icon and menu,
XDG autostart, desktop notifications (Freedesktop specification), global shortcuts,
and clipboard integration.
No later-phase features are included here. Project licensing remains undecided; no license was assigned.
