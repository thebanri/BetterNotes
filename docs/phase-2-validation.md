# Phase 2 validation

Validated on 2026-09-20 on CachyOS, using Rust/Cargo 1.98.1, GCC 16.2.1,
Qt 6.11.2, and system SQLite 3.53.4. No system packages were installed.

## Changes

Plain-text notes can be created, selected, edited, deleted after confirmation,
automatically saved and reopened in one main window. SQLite migrations and CRUD,
draft handling and conflict detection live in the Rust core. The QML adapter
exposes read-only state and explicit operations; a one-shot QML timer requests a
save 500 ms after the last edit. Pending edits are also saved before switching,
creating or closing. Save failures retain the draft. XDG paths are centralized in
the Rust `paths` module. See [architecture](architecture.md) for the decisions.

Created:

- `app/src/notes_bridge.rs`
- `app/tests/notes_flow.qml`
- `crates/core/src/notes.rs`
- `crates/core/src/paths.rs`
- `crates/core/src/session.rs`
- `crates/core/src/store.rs`
- `crates/core/tests/persistence.rs`
- `migrations/0001_notes.sql`
- `docs/phase-2-validation.md`

Modified:

- `Cargo.toml`, `Cargo.lock`, `app/Cargo.toml`, `crates/core/Cargo.toml`
- `app/build.rs`, `app/src/main.rs`, `crates/core/src/lib.rs`
- `qml/windows/Main.qml`, `README.md`, `docs/architecture.md`

The owner's preexisting AGENTS.md change is preserved and excluded from the phase
commit. No user note data was used in tests or modified by validation.

## Commands and results

| Command | Result |
| --- | --- |
| `cargo fetch` | Succeeded; resolved SQLite and test dependencies. |
| `cargo fmt` | Succeeded. |
| `cargo fmt --check` | Succeeded. |
| `cargo check --locked` | Succeeded. |
| `cargo test --locked` | Succeeded: 13 tests passed, 0 failed (1 Qt integration, 3 core unit tests, 9 persistence tests including a subprocess helper). |
| `cargo build --locked` | Succeeded; produced the Qt/QML application binary. |
| `/usr/lib/qt6/bin/qmllint --max-warnings 0 -I target/cxxqt/qml_modules qml/windows/Main.qml` | Succeeded with no diagnostics. |
| `cargo metadata --locked --format-version 1` | Succeeded; inspected resolved compiler requirements. |

Core tests cover Unicode and SQL-shaped text, create/read/update/delete, file
reopening, schema rollback and repeated migrations, rejection of future/unrelated/
corrupt/incomplete databases, XDG fallback rules, save-before-navigation, explicit
discard/delete, and retained drafts after locked or conflicting writes. A child
process exits without destructors while a transaction is open: reopening recovers
the committed note and omits the uncommitted insert.

The Qt test uses a temporary XDG data directory, the actual embedded Main.qml,
the offscreen platform and software renderer. It edits the real text controls,
waits for autosave, switches notes with a pending draft, deletes a note, and closes
with unsaved content. Rust then reopens SQLite and verifies the exact stored text.
The intentional missing-resource test prints Qt's expected error. During
development, the test fixture's QObject lookup was corrected to use
ApplicationWindow.contentData; the final test succeeds.

The compiled executable was also launched from `/tmp`, with a fresh temporary
XDG_DATA_HOME, `QT_QPA_PLATFORM=offscreen`, `QT_QUICK_BACKEND=software`, and
`QT_FORCE_STDERR_LOGGING=1`, under `timeout 3s`. It printed
`BetterNotes: application window loaded` without QML errors. Exit 124 was the
intentional timeout of the running event loop. SQLite checks on that isolated
database returned schema version `1`, journal mode `wal`, integrity `ok`, and
zero notes. The startup check creates no sample notes.

## Limits

- Only one ordinary application window is provided. Independent sticky windows
  and their geometry persistence belong to Phase 3.
- The final check/build still reports GCC's `-Wsfinae-incomplete` warning in Qt's
  `qchar.h`, as in Phase 1. It does not prevent compilation or linking.
- One scoped qmllint suppression covers `Qt.inputMethod.commit()`, whose method
  is absent from the installed QML metadata's QObject type. It is an official Qt
  API and is exercised by the close-time test.
- Physical input devices, IME composition, real Wayland/X11 sessions, and all
  target desktops have not been manually validated. Other Qt/compiler versions
  and the Ubuntu package recipe still need host-specific validation.
- SQLite calls are synchronous. Lock waits are bounded at 250 ms; large notes or
  slow disks can still pause the GUI. Note lists currently load all titles.
- Forced termination can lose edits since the last successful save. The process
  exit test does not simulate a physical power failure or faulty storage.
- No IPC or automatic cross-process list refresh is included. Revision checks
  reject stale writes; explicit Reload updates the view and confirms draft loss.

The next phase, when requested, is Phase 3 — Sticky Windows. It was not started.
