# Architecture

Decision date: 2026-09-20. BetterNotes remains a development codename.

The repository initially contained only AGENTS.md. Phase 1 establishes a Linux
desktop executable, an embedded QML window, and the Rust/Qt boundary. It adds no
storage, note operations, desktop services, async runtime, or background workers.

## Integration decision

Use CXX-Qt 0.9.0 with Cargo and system Qt 6. Keep the binding crates on the same
release and commit Cargo.lock. The choice prioritizes maintained Qt 6 integration,
explicit ownership, and a small application bridge over broad API coverage.

| Option | Assessment |
| --- | --- |
| [CXX-Qt](https://github.com/KDAB/cxx-qt/releases) | Maintained KDAB project with Qt 6 support, generated QObjects, properties, signals/slots, QML registration, threading facilities and Cargo/CMake examples. Selected. |
| [qmetaobject-rs](https://github.com/woboq/qmetaobject-rs) | Concise QML integration, but upstream explicitly describes passive maintenance. Less suitable for a new long-lived project. |
| [Qt Bridge for Rust](https://www.qt.io/blog/qt-bridges-public-beta-for-rust) | Official Qt effort supporting properties, methods, signals, collections and cross-thread calls. Public beta announced July 2026; promising, but less established for this foundation. |
| Handwritten C++ shim with CXX | Viable with stable Qt APIs, but would require maintaining our own QObject/property/model glue. Reserve small shims for APIs missing from CXX-Qt. |

CXX-Qt does not wrap every Qt API. Future list models may need explicit Qt model
adapters; domain types must stay in the core. QObject access stays on Qt's GUI
thread. If later work needs workers, use queued delivery rather than sharing GUI
objects between threads. No workers are required now.

## Layout and ownership

- `crates/core`: Qt-independent Rust; currently only application identity.
- `app`: executable lifecycle and thin Rust QObject adapter for QML.
- `qml`: presentation, layout and window behavior, embedded as Qt resources.
- `docs`: architectural decisions and validation evidence.

Cargo invokes CXX-Qt code generation, the C++ compiler, and Qt's build tools.
A second CMake project is unnecessary for this Cargo-only application. System Qt
remains dynamically linked; future packages must include Qt libraries, QML imports
and platform plugins. Embedding QML avoids a dependency on the working directory.

Qt selects the platform plugin. No X11-only positioning or always-on-top behavior
is assumed. Wayland/X11 and desktop compatibility need real-session testing;
headless loading alone cannot certify them.

License selection is deferred to the project owner. No project license is assigned
by this foundation; distribution will also need to account for dependency licenses.

## Phase 2 — Basic Notes

The Qt integration and Cargo build remain unchanged. Persistence and editor
behavior are implemented as focused modules in the existing Rust core. A separate
database crate is unnecessary for this small schema and would add a dependency
boundary without another consumer yet. SQL is confined to `store.rs`; domain
types and the editing session do not depend on QML. Linux filesystem conventions
are confined to `paths.rs` and exposed through ordinary Rust functions.

Use [rusqlite](https://docs.rs/rusqlite/0.40.2/rusqlite/) with system SQLite.
Synchronous, parameterized queries keep the implementation small and require no
runtime, connection pool or worker thread. The 250 ms SQLite busy timeout bounds
lock waiting; slow disks or large notes can still pause the GUI. Measure that
before introducing a worker. `thiserror` provides explicit errors, and `tempfile`
is used only for isolated tests. No serialization format is needed in this phase.

`migrations/0001_notes.sql` creates only the notes table: stable integer ID, title,
plain-text body, creation/modification timestamps (Unix milliseconds), and a
revision counter. The ID is not reused after deletion. List queries retrieve only
IDs and titles; only the selected note's body is loaded. Newest-created notes
appear first, and editing does not reorder the list.

Migration and version updates share an immediate transaction. `user_version`
records the schema and `application_id` identifies a BetterNotes database. Unknown
schemas, unrelated nonempty databases and corrupt databases produce errors;
there is no reset/delete/recreate recovery path. Each note mutation is one atomic
SQL statement. Conditional revision checks reject stale updates/deletions from
another process. This is data protection, not Phase 9 single-instance IPC.

WAL journaling with `synchronous=FULL` is used for committed-write durability;
see [SQLite's synchronization documentation](https://www.sqlite.org/pragma.html#pragma_synchronous).
Pending drafts remain in memory until saved. A crash can lose edits since the last
successful save, and software cannot guarantee durability against faulty hardware.
Interrupted-process tests verify recovery of committed WAL records and rollback
of an incomplete transaction, not physical power-loss behavior.

`NotesSession` owns the draft, dirty state, save-before-switch/create policy,
explicit discard/reload and confirmed deletion. It clears dirty state only after
a successful write. The Qt adapter exposes read-only properties and invokes these
operations. QML supplies list/editor controls, confirmations, and a 500 ms one-shot
timer triggered by edits; it contains no SQL or persistence decisions. Normal
window closure calls the same Rust save operation and is rejected on failure.

The database path follows the [XDG Base Directory specification](https://specifications.freedesktop.org/basedir/0.8/).
Only the data path is needed now. Relative/empty XDG_DATA_HOME is ignored, and an
absolute HOME fallback is required. App-created directories use mode 0700;
existing directory permissions are left intact. Configuration/cache/state paths
will be added to the same boundary when a requested feature actually needs them.

This phase supplies one application window. It does not add sticky windows,
rich text, search, tags, reminders, tray integration, IPC or import/export.

## Phase 3 — Sticky Windows

Keep CXX-Qt and the Phase 2 store/session design. The main window is now a note
library, and each independent `StickyNote.qml` contains its own NotesBackend and
Rust editing session. A session opened for a sticky loads only that note. The
library refreshes its titles after saves/deletions. The library's QML registry
owns window objects and enforces one editor per note per process; IDs cross the
bridge as strings so JavaScript number precision cannot confuse note identities.
No global session state, worker, new dependency or platform service is needed.
Each editor has a SQLite connection; existing revision checks continue to protect
against edits from other processes. Window objects are destroyed on close.

The QObject parent keeps lifetimes explicit, while `transientParent: null` and
ordinary Qt window flags make notes independent top-level windows. Native title
bars and borders provide moving, resizing and minimizing through the compositor.
This avoids custom drag-coordinate handling, and works with Qt versions before
the newer QML system-move helpers. See [Qt Window ownership and transient parents](https://doc.qt.io/qt-6/qml-qtquick-window.html#transientParent-prop).
Collapse hides the editor and reduces height; the expanded size is retained.

Migration 2 adds `note_windows`, keyed by note ID with `ON DELETE CASCADE`.
The upgrade and schema version change are transactional and preserve existing
notes. Old Phase 2 binaries reject schema 2 rather than attempting a downgrade.
Window snapshots contain normal expanded client size, optional position, display
name, collapsed state and whether to reopen. They do not change content revisions.
The core validates sizes and coordinates, and SQLite enforces basic constraints.
Content and geometry each use an edit/event-driven 500 ms single-shot timer;
normal close and quit flush pending work without constant polling.

Closing a note saves it and marks its window closed. Closing the library or
choosing Quit first saves every open editor and records each as open for restart;
only when all succeed are any windows closed. Failure retains the windows and
drafts, although earlier successful writes remain committed. Confirmed deletion
removes the note and its window state. A separate confirmed discard-and-close
action provides recovery from unrecoverable storage errors without deleting the
saved note. If its geometry write fails, the previous reopening flag remains.

The platform capability decision lives in `app/src/platform.rs`, exposed by the
ApplicationInfo adapter. QML supplies the actual [Qt platform plugin](https://doc.qt.io/qt-6/qml-qtqml-qt.html#platform-prop),
including xcb under XWayland. Only xcb (and offscreen tests) uses absolute x/y.
On Wayland, positions are neither saved nor set; the compositor chooses them.
See [QWindow position limitations](https://doc.qt.io/qt-6/qwindow.html#position).
QML's `windows/WindowPlacement.js` handles visual geometry fitting. Screen/size
restoration and activation are hints, especially on tiling desktops.
Missing displays fall back to the library/current screen, dimensions and X11
coordinates are clamped to display bounds, and screen-list changes trigger
recovery. Bring here provides a manual recovery action. ScreenInfo does not expose
per-screen work areas; margins reduce decoration overlap but cannot guarantee
avoidance of every panel. There is no workspace, desktop-layer or always-on-top
integration. Minimized/maximized state is not persisted: reopening uses ordinary
windows so notes remain discoverable.

Qt integration tests now use a standalone Cargo test executable (`harness=false`)
to create and destroy Qt objects on the process main thread. The shared engine
loader retains Phase 1's resource-error handling. The test uses real embedded
QML windows and isolated temporary storage; it does not certify real compositor
interaction or native decoration drag/resize behavior.
