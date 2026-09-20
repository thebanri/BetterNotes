# Phase 1 architecture

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
