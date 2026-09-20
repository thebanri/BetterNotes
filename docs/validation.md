# Phase 1 validation

Validated on 2026-09-20, CachyOS Linux (Arch family), x86_64.

## Environment inspected

- `rustc --version`: 1.98.1
- `cargo --version`: 1.98.1
- `c++ --version`: GCC 16.2.1
- `cmake --version`: 4.4.3 (not used by the selected build)
- `pkg-config --modversion Qt6Core Qt6Qml Qt6Quick`: 6.11.2 for all three
- `pacman -Q`: qt6-base 6.11.2-3.1, qt6-declarative 6.11.2-2.1,
  qt6-wayland 6.11.2-1.1; compiler and Rust packages present
- `qmake6`: `/usr/bin/qmake6`
- QML linter: `/usr/lib/qt6/bin/qmllint`

No additional system packages were required or installed. Ninja was not found
and is not required. README documents installation requirements for a fresh host.

## Commands and outcomes

| Command | Result |
| --- | --- |
| `cargo fetch` | Succeeded; Cargo.lock generated. Initial sandbox DNS restriction was resolved after network access was enabled. |
| `cargo metadata --format-version 1 --locked` | Succeeded; checked declared Rust version requirements of resolved dependencies. |
| `cargo fmt` | Succeeded. |
| `cargo fmt --check` | Succeeded, including the final source state. |
| `cargo check` | Succeeded after correcting the signal callback's `Send` requirement. |
| `cargo test` | Succeeded: 1 application smoke test passed, 0 failed; core and doc-test targets currently contain 0 tests. |
| `cargo build` | Succeeded; produced `target/debug/betternotes`. |
| `/usr/lib/qt6/bin/qmllint -I target/cxxqt/qml_modules qml/windows/Main.qml` | Succeeded with no output. |
| `git diff --check` | Succeeded during the initial implementation review. |
| `ldd target/debug/betternotes` | System Qt shared libraries resolved; no missing dependencies reported. |

The first compiler check rejected `Rc<Cell<bool>>` in the signal callback because
CXX-Qt requires `Send` closures. The final implementation uses `Arc<AtomicBool>`;
this does not introduce a background thread.

Executed from `/tmp`, to verify independence from the repository working directory:

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 3s \
  /absolute/path/to/BetterNotes/target/debug/betternotes
```

Output: `BetterNotes: application window loaded`. No QML errors appeared.
Exit status **124** was the intentional timeout of the running event loop, not a
normal application exit. The automated smoke test also checks the error path for
a nonexistent embedded QML resource.

## Known limitations

- GCC 16 reports `-Wsfinae-incomplete` in Qt's `qchar.h` while compiling generated
  bridge code. Checks, tests and linking succeed; the warning is not suppressed.
- No real Wayland/X11 desktop session, keyboard interaction, window closure or
  multi-desktop compatibility was manually validated. Offscreen success does not
  certify compositor behavior or appearance.
- Only the listed toolchain and Qt version were tested. Other Linux distributions
  and the documented Ubuntu package recipe need validation on those hosts.
- Qt can abort before Rust startup handling if the platform plugin cannot load;
  Qt emits its own diagnostics in this case.
- This is a dynamically linked development build, not a distributable package.
- Phase 2 and later features are intentionally absent. No final product name or
  license has been selected.

## File inventory

All foundation files are new relative to the starting repository:

```text
.cargo/config.toml
.gitignore
Cargo.toml
Cargo.lock
README.md
app/Cargo.toml
app/build.rs
app/src/main.rs
app/src/bridge.rs
crates/core/Cargo.toml
crates/core/src/lib.rs
qml/qml.qrc
qml/windows/Main.qml
docs/architecture.md
docs/validation.md
```

Existing files modified by the implementation: none. The owner's subsequent
AGENTS.md workflow update is preserved locally and excluded from the application
commit. Build output under `target/` and the generated `app/.qmlls.ini` are ignored.

## Commit preparation

The phase was revalidated after the owner requested the Git/GitHub workflow:
`cargo fmt --check`, `cargo check --locked`, `cargo test --locked`,
`cargo build --locked`, and the QML linter all succeeded. The test count remains
1 passed, 0 failed. The Qt header warning described above remains present.

The current branch is `main`, tracking `origin/main`. At review time, the existing
commit contained only AGENTS.md; the foundation files had not yet been committed.
They are prepared as `feat: complete phase 1 foundation`. Commit and push results
are reported separately after the actual Git commands run.

Next requested phase: add SQLite, migrations, the Rust note model, note CRUD,
autosave and persistence, with migration and data integrity tests. This work was
not started during Phase 1.
