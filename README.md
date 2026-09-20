# BetterNotes

Linux-first desktop notes application, currently at **Phase 1 — Foundation**.
BetterNotes is a working codename. This preview opens a basic Qt Quick window;
note editing and persistence are not implemented yet.

## Architecture

Rust owns application behavior; QML owns presentation. A Qt-independent
`betternotes-core` crate supplies application identity through a small CXX-Qt
adapter in the executable. QML is embedded in the binary as Qt resources.

```text
Cargo.toml              Rust workspace
crates/core/src/lib.rs  Qt-independent core
app/build.rs            CXX-Qt code generation and Qt resources
app/src/main.rs         Qt lifecycle and startup errors
app/src/bridge.rs       Rust QObject exposed to QML
qml/windows/Main.qml   Basic application window
qml/qml.qrc            Embedded UI resource manifest
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

On Arch Linux / CachyOS:

```sh
sudo pacman -S --needed base-devel rust qt6-base qt6-declarative qt6-wayland
```

If using rustup instead of distribution Rust, use the stable toolchain with
`rustup component add rustfmt`. Do not install a second conflicting Rust provider.
The Qt packages include development tools and QML modules on Arch.
([Qt base package](https://archlinux.org/packages/extra/x86_64/qt6-base/),
[Qt Wayland package](https://archlinux.org/packages/extra/x86_64/qt6-wayland/))

On Ubuntu 24.04 or newer, install the system build and Qt packages, then provide
a current stable Rust toolchain (older distro Rust may be insufficient):

```sh
sudo apt install build-essential pkg-config \
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

Close the window with its Close button, the window manager, or Ctrl+Q. Tab and
Enter navigate/activate the button. Application identity displayed in the window
comes from Rust through QML method calls. Startup diagnostics go to stderr; QML
load failure returns a nonzero exit status instead of leaving an invisible process.

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

`cargo test` runs a headless Qt smoke test using the offscreen platform and software
renderer. It loads the actual embedded window and checks that a missing resource
returns an error. Qt's expected missing-resource warning appears during this test.
The core has no domain behavior to test yet. Headless tests do not establish
visual quality, keyboard interaction or compositor compatibility.

To keep a headless executable running briefly for a manual startup check:

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software timeout 3s target/debug/betternotes
```

The successful startup line should appear without QML errors. Timeout status 124
means the event loop remained running until the timeout; it is not a graceful exit.
See [the validation report](docs/validation.md) for commands and actual results.

## Scope and next phase

Phase 2 should add SQLite migrations, the Rust note model, create/edit/delete,
autosave and persistence, with data integrity tests. No later-phase functionality
is included here. Project licensing remains undecided; no license was assigned.
