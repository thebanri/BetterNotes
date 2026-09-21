# Contributing to BetterNotes

Thank you for your interest in contributing to BetterNotes! BetterNotes is an open-source, Linux-first sticky notes and desktop workspace application built with Rust and Qt 6/QML.

## Philosophy & Guiding Principles

1. **Linux-First Quality:** Wayland and X11 are first-class targets across GNOME, KDE Plasma, XFCE, Cinnamon, MATE, Budgie, Hyprland, and Sway.
2. **Clear Architectural Boundaries:**
   - **Rust owns:** domain logic, persistence, SQLite, search, reminders, attachments, filesystem, and IPC.
   - **QML owns:** presentation, layout, visual interactions, keyboard shortcuts, and animations.
3. **Data Sovereignty:** Offline-first, no telemetry, no cloud dependency, user data stored strictly in standard XDG directories.
4. **Safety & Stability:** No premature abstractions, graceful degradation when optional desktop features are unavailable, atomic writes to protect user data.

## Development Setup

### System Prerequisites

- **Rust:** Stable toolchain (1.88+ recommended).
- **C++ Compiler:** GCC or Clang supporting C++17.
- **Qt 6:** Core, Gui, Qml, Quick, QuickControls2, and Wayland plugins.
- **SQLite 3:** Development headers and pkg-config.
- **GUI tests:** The QtTest QML module (on Debian/Ubuntu: `qml6-module-qttest`).
  The editor assertions read selection formatting through Qt 6.7+ test APIs.

```bash
# Arch Linux / CachyOS
sudo pacman -S --needed base-devel rust sqlite pkgconf qt6-base qt6-declarative qt6-wayland

# Ubuntu / Debian
sudo apt install build-essential pkg-config libsqlite3-dev \
  qt6-base-dev qt6-base-dev-tools qt6-declarative-dev qt6-declarative-dev-tools \
  libqt6core6 libqt6gui6 libqt6qml6 libqt6quick6 qml6-module-qtquick-controls
```

## Running & Testing

Always verify before submitting a pull request:

```bash
# Check code formatting
cargo fmt --check

# Run compiler and Clippy linter
cargo clippy --all-targets --all-features -- -D warnings

# Run all test suites
cargo test --locked

# Build release binary
cargo build --release
```

## Git Workflow & Commits

We follow Conventional Commits:

- `feat: ...` for new features
- `fix: ...` for bug fixes
- `docs: ...` for documentation changes
- `test: ...` for adding or improving tests
- `refactor: ...` for internal structural improvements

## Pull Request Guidelines

1. Create a dedicated feature branch from `main`.
2. Keep commits atomic and focused.
3. Ensure all tests pass and formatting conforms to `cargo fmt`.
4. Document any new desktop/compositor interactions or limitations.

## Translations

Interface texts are marked with `qsTr()` in QML. After adding or changing
texts, run `translations/update.sh` (needs Qt's `lupdate` and `lrelease`),
translate the new entries in `translations/qml_<lang>.ts` (Qt Linguist, or by
hand), and run the script again. It rebuilds `qml/windows/i18n/qml_<lang>.qm`,
which the app embeds. `qml_en.ts` holds only English plural forms, so write
texts with a count as `qsTr("%n note(s)", "", count)`.
