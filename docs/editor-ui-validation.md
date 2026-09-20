# Sticky editor and settings fixes

Validated on 2026-09-21 with Rust 1.98.1 and Qt 6.11.2.

## Changes and decisions

- Formatting buttons retain the body selection and operate on that exact range.
  Bold, italic, underline, text color and H1/H2 no longer remove and reinsert text
  or rewrite the document with HTML regular expressions. An empty selection is a
  no-op; it never reuses a stale selection or inserts placeholder text.
- `TextFormatter` is a small presentation adapter registered by the existing
  CXX-Qt build. It uses Qt's public
  [QTextCursor merge operations](https://doc.qt.io/qt-6/qtextcursor.html#mergeCharFormat)
  on the editor's
  [QQuickTextDocument](https://doc.qt.io/qt-6/qquicktextdocument.html#textDocument).
  Each operation changes only its requested properties. This preserves mixed
  formatting, images, text and undo/redo. Rust continues to own persistence and
  settings; there is no new application dependency or schema migration.
- H1/H2 are selection-sized visual heading presets (2×/1.5× the note's base size
  and bold); clicking the same preset again restores body size. They intentionally
  do not expand a partial selection to the entire paragraph or add semantic HTML
  heading blocks.
- The first plain-to-rich conversion escapes literal HTML and preserves line
  breaks. Ordinary edits no longer feed serialized HTML through a live backend
  binding into the same document. External reloads still update the editor.
- The top bar is a pill with a transparent container. The window's own background
  is rounded too, so an opaque rectangular surface no longer fills the corners.
  The note body remains opaque. Frameless flags follow Qt's
  [window transparency guidance](https://doc.qt.io/qt-6/qml-qtquick-window.html#color-prop).
- Layout-managed items use layout sizes; the formatting bar fits the 240px
  minimum width. Scroll content follows the viewport width, minimum editor space
  is reserved, and vertical padding adapts at small heights. Moving/resizing uses
  the existing native Qt system operations.
- Settings use 24px horizontal padding, rounded sections, themed selectors, a
  preview, and keyboard-accessible palette buttons. Pastel, Vivid and Earth
  palettes contain 18 choices in total. A color dialog and validated hexadecimal
  entry allow arbitrary colors, saved through the existing Rust settings API.
  Color/font persistence failures are shown instead of claiming a successful save.
- Settings are transient for their note and use system dragging. Absolute
  centering is only attempted where the existing platform policy permits it.

## Files

Created:

- `app/src/text_formatter.h`
- `app/src/text_formatter.cpp`
- `docs/editor-ui-validation.md`

Modified:

- `app/build.rs`
- `app/tests/notes_flow.qml`
- `app/tests/qml.rs`
- `qml/windows/StickyNote.qml`
- `qml/windows/StickyNoteSettingsModal.qml`
- `docs/architecture.md`
- `CONTRIBUTING.md`

The pre-existing user modification to `AGENTS.md` is excluded from this change.

## Validation

| Command | Result |
| --- | --- |
| `cargo fmt --check` | Passed. |
| `cargo check --locked` | Passed. |
| `cargo test --locked` | Passed: 47 Rust tests and the Qt/QML integration executable. |
| `cargo test --locked --test qml -- --capture-ui` | Passed; offscreen note/settings screenshots inspected. Optional snapshots are written to `/tmp/betternotes-note.png` and `/tmp/betternotes-settings.png`. |
| `QT_SCALE_FACTOR=1.5 cargo test --locked --test qml` | Passed at 150% scaling. |
| `cargo build --locked` | Passed; `target/debug/betternotes`. |
| `cargo build --release --locked` | Passed; `target/release/betternotes`. |
| `/usr/lib/qt6/bin/qmllint --max-warnings 0 -I target/cxxqt/qml_modules qml/windows/StickyNote.qml qml/windows/StickyNoteSettingsModal.qml` | Passed without diagnostics. |
| `clang-format --dry-run --Werror --style='{BasedOnStyle: LLVM, IndentWidth: 4}' app/src/text_formatter.h app/src/text_formatter.cpp` | Passed. |
| `git diff --check` | Passed. |

The expanded QML test sends mouse clicks to the actual toolbar and color buttons
and exercises Ctrl+B. It covers overlapping styles, repeated words, literal HTML,
Unicode, multiline selections, undo/redo, default-color reset, no-selection
behavior, save/reopen, custom-color validation and persistence, the color dialog,
settings padding, and repeated resizing through 240×180, 800×600, 260×220 and
380×360 followed by collapse/expand.

The test now isolates `XDG_CONFIG_HOME` as well as data storage, keeping autostart
checks away from personal configuration. The first full test attempt was blocked
by the sandbox's prohibition on binding a Unix IPC socket (`Operation not
permitted`). The authorized run outside that restriction passed.

Qt headers produce an existing GCC `QChar`/SFINAE warning during C++ compilation.
The QML harness deliberately logs a missing-resource error and a stale-write error
for failure-path coverage. Offscreen runs also report unsupported raise/size-hint
operations; these do not fail the assertions.

## Limits and next check

Tests use Qt's offscreen software renderer. They validate layout and application
behavior, not GPU/compositor behavior during a live Wayland/X11 resize. Check the
new release binary in the target desktop session, including rounded transparency,
continuous edge/corner drags, and settings at fractional scaling. Unsupported
compositor placement/stacking remains subject to the existing platform limitations.

The initial plain-to-rich conversion starts a new document undo history; format
changes after conversion remain undoable. Existing rich-text detection and the
storage/export format remain unchanged by this fix.
