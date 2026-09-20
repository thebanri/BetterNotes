# BetterNotes

Linux-first desktop notes application, currently at **Phase 2 — Basic Notes**.
BetterNotes is a working codename. Create, edit and delete plain-text notes in one
main window, with autosave and local SQLite persistence. Independent desktop
sticky windows belong to Phase 3.

## Architecture

Rust owns application behavior; QML owns presentation. A Qt-independent
`betternotes-core` crate owns notes, SQLite migrations, persistence and draft
state. A CXX-Qt adapter exposes this state to QML, which is embedded as Qt resources.

```text
Cargo.toml              Rust workspace
crates/core/src/lib.rs  Qt-independent core
crates/core/src/store.rs SQLite persistence and migrations
crates/core/src/session.rs Draft state and save-before-navigation rules
crates/core/src/paths.rs Linux XDG data path resolution
app/build.rs            CXX-Qt code generation and Qt resources
app/src/main.rs         Qt lifecycle and startup errors
app/src/notes_bridge.rs Notes QObject exposed to QML
qml/windows/Main.qml   Notes list and editor
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

Use **New note** (Ctrl+N), choose a note from the list, and edit its title or body.
Tab navigates controls; Up/Down selects notes when the list has keyboard focus.
Ctrl+S saves immediately. Close with the window manager or Ctrl+Q.

After 500 ms without an edit, a one-shot timer saves the draft. Selecting another
note, creating a note, and closing the window also save pending edits immediately.
The status shows whether changes remain unsaved. Delete requires confirmation;
it permanently removes the selected note, including its pending draft.

Database errors appear in the window and on stderr. Failed saves keep the draft
and block navigation or closure that would lose it. Use **Save again** to retry a
save, or repeat the failed operation after resolving its cause. **Reload** reads
the saved notes again and asks before discarding a pending draft. When another
process edited/deleted the same note, copy any unsaved text before reloading.
Startup storage errors disable editing and offer **Retry opening**; they never
silently switch to temporary storage or replace the database.

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

## Validation

`cargo test` checks CRUD, reopening saved data, migrations and rollback, concurrent
edits, failed writes, crash recovery and XDG paths. A headless Qt test exercises the
actual QML editor, its autosave timer, selection, deletion and close-time saving.
Tests use temporary data directories, not your real notes. Qt's expected
missing-resource warning appears during the error-path test. Headless tests do
not establish visual quality, physical keyboard interaction or compositor compatibility.

To keep a headless executable running briefly for a manual startup check:

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 3s target/debug/betternotes
```

The successful startup line should appear without QML errors. Timeout status 124
means the event loop remained running until the timeout; it is not a graceful exit.
See [the Phase 2 validation report](docs/phase-2-validation.md) for commands and
actual results; [the original report](docs/validation.md) records Phase 1.

## Scope and next phase

Phase 2 includes SQLite migrations, the Rust note model, create/edit/delete,
autosave and persistence. Phase 3 should add independent sticky windows and window
state persistence while respecting Wayland restrictions. No later-phase features
are included here. Project licensing remains undecided; no license was assigned.
