# Phase 3 validation

Validated on 2026-09-20 with Rust/Cargo 1.98.1, GCC 16.2.1, Qt 6.11.2 and
system SQLite 3.53.4 on CachyOS. No dependencies or system packages were added.

## Result and decisions

Notes open in independent, natively decorated windows. Each has an isolated Rust
editing session and autosave timer; the library prevents duplicate editors within
the process. Moving/resizing uses native decorations. Collapse/expand retains
expanded size. Closing one window preserves its note; quitting restores the set
of windows that remained open. A save failure prevents normal close/quit, with a
confirmed discard-and-close recovery action available.

Migration 2 adds a separate window-state table with cascading cleanup on note
deletion. Window writes do not increment note revisions. Qt platform capability
policy lives in Rust's app/src/platform.rs; QML's WindowPlacement.js fits visual
geometry to displays. Wayland does not store
or restore absolute positions. See [architecture](architecture.md) for details.

Created:

- `app/src/engine.rs`
- `app/src/platform.rs`
- `app/tests/qml.rs`
- `crates/core/src/window_state.rs`
- `crates/core/tests/window_persistence.rs`
- `migrations/0002_note_windows.sql`
- `qml/windows/WindowPlacement.js`
- `qml/windows/StickyNote.qml`
- `docs/phase-3-validation.md`

Modified:

- `app/Cargo.toml`, `app/src/main.rs`, `app/src/notes_bridge.rs`
- `app/src/bridge.rs`
- `app/tests/notes_flow.qml`
- `crates/core/src/lib.rs`, `crates/core/src/notes.rs`
- `crates/core/src/session.rs`, `crates/core/src/store.rs`
- `qml/qml.qrc`, `qml/windows/Main.qml`
- `README.md`, `docs/architecture.md`

The owner's preexisting AGENTS.md modification is preserved and excluded from
the phase commit. Tests and startup checks used temporary data, not user notes.

## Commands and actual results

| Command | Result |
| --- | --- |
| `cargo fmt` | Succeeded. |
| `cargo fmt --check` | Succeeded. |
| `cargo check --locked` | Succeeded. |
| `cargo test --locked` | Succeeded: 17 Rust tests (3 unit, 9 existing persistence including a subprocess helper, 5 new window persistence), plus the standalone Qt/QML integration executable. |
| `cargo build --locked` | Succeeded, including embedded QML resources. |
| `/usr/lib/qt6/bin/qmllint --max-warnings 0 -I target/cxxqt/qml_modules qml/windows/Main.qml qml/windows/StickyNote.qml` | Succeeded without diagnostics. |
| `git diff --check` | Succeeded. |

New Rust tests cover upgrading schema 1 without losing notes, repeated opening,
failed migration rollback, multiple window states, nullable Wayland coordinates,
closed versus deleted notes, cascading deletion, independent editor drafts,
rejection of invalid/locked state writes and retaining a deleted note's draft
instead of silently switching to another note.

The Qt test edits actual QML controls in simultaneous windows, waits for autosave
and geometry debounce, checks duplicate-window prevention, simulates an external
edit conflict and failed quit, closes one note without deleting it, deletes a
different note, collapses/expands, closes and reopens the library, and verifies
both contents and saved window state directly through Rust. Pure placement cases
cover negative monitor coordinates, a missing display, oversized/offscreen
geometry and the Wayland capability gate.

The GUI test moved out of libtest worker threads into a `harness=false` executable
so Qt is created and destroyed on the process main thread. This eliminated the
timer-thread shutdown diagnostic seen during development. Expected diagnostics
remain for the deliberately missing resource, simulated edit conflict, and the
offscreen plugin's unsupported `propagateSizeHints()` operations. GCC still emits
the preexisting Qt `qchar.h` SFINAE warning; compilation/linking succeed.

A separate Python-driven startup check seeded two notes and schema-2 window
states in a temporary XDG directory, then ran the compiled binary from `/tmp`
under `timeout 3s`, with Qt offscreen/software rendering. Startup printed
`BetterNotes: application window loaded`, without QML errors. Exit 124 was the
intentional event-loop timeout. SQLite integrity was `ok`. An oversized note
on a disconnected display was recovered to `(16, 40, 768, 720)` on the offscreen
800×800 display; the other retained its collapsed state and 380×360 expanded size.

## Limitations and next step

Physical dragging, native decoration behavior, real Wayland/X11 compositors,
monitor hotplug and IME input have not been manually tested. Tiling compositors
may override size, collapse height, screen and activation requests. X11 placement
is best effort; Wayland absolute placement is deliberately absent. Display bounds
are used instead of per-monitor panel work areas. Bring here remains available
for manual recovery. Minimized/maximized state is not persisted.

Storage operations remain synchronous, with 250 ms lock waits per operation.
Each editor owns a connection and only its own note body. The library loads all
titles. Across separate processes, content revisions reject stale edits, but the
last successful geometry write wins. No single-instance or IPC support is added.
Abrupt termination may lose text or geometry since the last successful save.

Phase 4 should add themes and polished, responsive components with high-DPI
validation. It was not started. Search, tray, shortcuts outside the application,
reminders, attachments, IPC and other later-phase features remain out of scope.
