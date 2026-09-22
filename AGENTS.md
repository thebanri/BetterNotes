# BetterNotes — Agent Development Guide

> `BetterNotes` is currently a working project name, not the final product name.

## 1. Project Vision

Build a production-quality, open-source, Linux-first sticky notes and desktop workspace application.

The application should feel:

* native
* lightweight
* fast
* modern
* privacy-friendly
* offline-first
* keyboard-friendly
* suitable for power users

The initial release targets Linux only.

Primary Linux environments:

* KDE Plasma
* GNOME
* XFCE
* Cinnamon
* MATE
* Budgie
* Hyprland
* Sway

Display systems:

* Wayland — first-class target
* X11 — first-class target

Windows and macOS are possible future targets, but they are NOT active development targets before Linux v1.0.

Do not sacrifice Linux integration quality for premature cross-platform support.

---

# 2. Technology Stack

Primary stack:

* Rust
* Qt 6
* QML
* SQLite
* SQLite FTS5
* serde
* Cargo
* Qt/CMake tooling where required

Tokio may be used only when asynchronous execution provides a meaningful benefit.

Do NOT replace the architecture with:

* Electron
* browser-based UI
* Python application core
* another GUI framework

unless explicitly requested.

If a major technical limitation requires reconsidering the stack, explain the limitation before changing anything.

---

# 3. Engineering Philosophy

Prefer:

* simple solutions
* maintainable code
* stable libraries
* small dependencies
* explicit behavior
* standards-based Linux integration
* graceful degradation
* testable architecture

Avoid:

* premature abstraction
* unnecessary async
* unnecessary background threads
* unnecessary polling
* large dependency trees
* hidden global state
* platform-specific logic scattered throughout the codebase
* speculative abstractions for Windows/macOS

Keep the project buildable after every meaningful change.

Never knowingly leave the repository in a broken state.

---

# 4. Agent Workflow

Before modifying code:

1. Inspect the repository.
2. Read this file completely.
3. Read `README.md`.
4. Read relevant Cargo manifests.
5. Read architecture/design documentation.
6. Inspect existing implementation before proposing replacements.

When implementing:

1. Make focused changes.
2. Avoid rewriting unrelated working code.
3. Follow existing architecture.
4. Run formatting.
5. Run compiler checks.
6. Run relevant tests.
7. Fix errors caused by the change.

After implementation, report:

* files created
* files modified
* important architectural decisions
* commands executed
* tests/build status
* known limitations
* recommended next step

Do not automatically continue into another development phase.

Stop when the requested task is complete.

---

# 5. Architecture

Maintain a clear separation between:

## Rust Core

Rust owns:

* application logic
* note domain logic
* database
* search
* tags
* attachments
* reminders
* clipboard services
* settings
* import/export
* backup/recovery
* IPC
* platform abstraction
* filesystem operations

## QML Presentation Layer

QML owns:

* presentation
* layouts
* user interaction
* visual state
* animations
* reusable visual components
* windows/dialogs/pages
* themes

QML must NOT contain database logic or significant business logic.

Rust must NOT contain unnecessary presentation logic.

---

# 6. Suggested Workspace Structure

The intended structure is approximately:

```text
betternotes/
├── AGENTS.md
├── Cargo.toml
├── Cargo.lock
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── SECURITY.md
├── CHANGELOG.md
│
├── crates/
│   ├── core/
│   ├── database/
│   ├── search/
│   ├── platform/
│   ├── ipc/
│   └── cli/
│
├── app/
│   └── src/
│
├── qml/
│   ├── components/
│   ├── windows/
│   ├── pages/
│   ├── dialogs/
│   └── themes/
│
├── migrations/
├── assets/
├── packaging/
│   └── linux/
└── tests/
```

This structure is guidance rather than an absolute requirement.

If a different structure is technically superior, explain why before performing a major restructuring.

---

# 7. Platform Abstraction

Platform-specific functionality must be isolated behind appropriate interfaces.

Conceptually:

```text
Platform
├── Linux
│   ├── Wayland
│   ├── X11
│   ├── DBus
│   ├── Freedesktop
│   └── XDG
│
├── Windows (future)
│   └── Win32
│
└── macOS (future)
    └── Cocoa
```

Do NOT implement Windows/macOS platform layers until explicitly requested.

However, avoid architectural decisions that make future implementations unnecessarily difficult.

---

# 8. Linux-First Requirements

Linux is not a secondary platform.

Linux desktop integration is a core feature.

The application should eventually support:

* native desktop behavior
* native notifications
* system tray where available
* desktop startup
* Wayland
* X11
* multi-monitor environments
* global shortcuts where available
* common desktop environments
* compositors such as Hyprland and Sway
* XDG filesystem conventions
* DBus/Freedesktop standards where appropriate

Prefer standard Linux mechanisms before desktop-specific hacks.

---

# 9. Wayland Rules

Wayland is a first-class target.

Do NOT assume X11 behavior is available on Wayland.

Investigate appropriate:

* Qt 6 Wayland functionality
* standard Wayland protocols
* XDG Desktop Portals
* compositor-specific functionality only when unavoidable

Important functionality includes:

* window positioning
* always-on-top behavior
* activation
* global shortcuts
* multi-monitor behavior
* workspace behavior
* system tray
* notifications
* fullscreen behavior

If functionality cannot reliably be implemented across generic Wayland compositors:

1. identify the limitation
2. explain why it exists
3. use a standard protocol if available
4. consider optional desktop/compositor integration
5. implement graceful fallback
6. document the limitation

Never pretend unsupported Wayland functionality works.

---

# 10. X11 Rules

X11 remains a first-class supported environment.

Use appropriate X11 mechanisms when required.

Keep X11-specific implementation behind the platform abstraction.

Do not leak X11 assumptions throughout application logic.

---

# 11. Desktop Environment Compatibility

Target:

* KDE Plasma
* GNOME
* XFCE
* Cinnamon
* MATE
* Budgie
* Hyprland
* Sway

Do not assume:

KDE == GNOME == XFCE.

Desktop-specific integrations must remain optional whenever possible.

Failure of optional desktop integration must not prevent the application from starting.

---

# 12. Startup / Autostart

The application must eventually support:

> Start application when I log in

Prefer standards such as XDG autostart where appropriate.

Typical location:

```text
$XDG_CONFIG_HOME/autostart/
```

Do not hard-code `$HOME/.config` when XDG environment variables should be respected.

Autostart must:

* require no root privileges
* be configurable
* start primarily in background
* avoid opening the full main window unnecessarily
* restore sticky notes when configured
* initialize tray/global shortcuts where available

Failure of optional integrations must not prevent startup.

---

# 13. Application Startup Sequence

Target startup sequence:

1. initialize configuration
2. initialize database
3. perform migrations
4. initialize platform services
5. initialize notification service
6. initialize tray if supported
7. initialize global shortcuts if supported
8. restore notes if configured
9. remain in background if configured

Startup should degrade gracefully when optional functionality is unavailable.

---

# 14. System Tray

Where supported, provide a tray menu containing approximately:

* New Note
* Quick Capture
* Search
* Show All Notes
* Hide All Notes
* Settings
* Start at Login
* Export
* Quit

The application must remain usable when a system tray is unavailable.

---

# 15. Notes

A note should eventually support:

* title
* rich text
* Markdown-compatible content
* checklists
* code blocks
* links
* images
* file attachments
* tags
* custom colors/themes
* priority
* creation date
* modification date
* reminder
* pinned state
* archived state

Sticky windows should eventually support:

* moving
* resizing
* collapsing
* pinning
* always-on-top where supported
* transparency where supported
* restoring position
* restoring size
* minimizing
* closing

Notes require:

* autosave
* crash safety
* reliable persistence

---

# 16. Multi-Monitor Behavior

Remember where practical:

* display
* position
* size
* visibility
* workspace where supported

If a previously used monitor is disconnected, notes must remain recoverable.

Never allow a note to become permanently inaccessible because its previous display disappeared.

---

# 17. Quick Capture

Preferred default shortcut:

```text
Ctrl + Alt + Space
```

The shortcut must be configurable.

Quick Capture should:

1. open a small capture window
2. allow immediate typing
3. create the note quickly
4. close or reset appropriately

Global shortcut availability differs across Wayland compositors.

Do not assume arbitrary global shortcuts always work.

Use standard mechanisms or documented fallbacks.

---

# 18. Command Palette

The application should eventually expose a command palette containing actions such as:

* New Note
* Quick Capture
* Search Notes
* Show All Notes
* Hide All Notes
* Pin
* Archive
* Export
* Import
* Settings
* Start at Login
* Quit

Design the command system so additional commands can be added cleanly.

---

# 19. Search

Use SQLite FTS5.

Search should eventually cover:

* title
* content
* tags
* attachment metadata

Target behavior:

* instant results
* keyboard navigation
* highlighting
* global search

Suggested default shortcut:

```text
Ctrl + K
```

It must be configurable.

---

# 20. SQLite

Expected domain tables include approximately:

* notes
* tags
* note_tags
* attachments
* reminders
* settings
* note_history

Use:

* migrations
* transactions
* foreign keys where appropriate
* indexes where justified
* safe queries

Protect user data.

Never silently delete data because of migration failure.

---

# 21. Attachments

Support:

* images
* arbitrary files

Preferred design:

SQLite stores attachment metadata.

Actual files live in the application data directory.

Example concept:

```text
$XDG_DATA_HOME/<app>/attachments/
```

Avoid storing large binary files directly inside SQLite unless there is a strong technical reason.

Requirements:

* safe filenames
* collision handling
* safe filesystem operations
* attachment metadata
* no automatic execution

Never execute an attachment merely because it was attached to a note.

---

# 22. Reminders

Support eventually:

* one-time reminders
* recurring reminders
* desktop notifications

Reminder functionality should work when the primary UI is not visible but the application is running.

Avoid high-frequency polling.

Prefer event/timer-based scheduling where practical.

---

# 23. Notifications

Expose a conceptual:

```text
NotificationService
```

Linux should use an appropriate Freedesktop-compatible mechanism.

Future platform implementations may use:

* Windows native notifications
* macOS native notifications

Do not implement future platform versions yet.

---

# 24. Global Shortcuts

Expose a conceptual:

```text
GlobalShortcutService
```

Potential shortcuts include:

* Quick Capture
* Search
* Command Palette

Linux implementation must account for Wayland restrictions.

Do not assume arbitrary application-wide global shortcut registration works on every compositor.

---

# 25. Window Management

Sticky notes are independent windows.

Support eventually:

* move
* resize
* collapse
* persistence
* multiple simultaneous notes
* always-on-top where supported
* multi-monitor restoration

Do not assume applications can arbitrarily position windows on every Wayland compositor.

Implement graceful behavior when positioning is unavailable.

---

# 26. XDG Data Paths

Respect:

```text
XDG_CONFIG_HOME
XDG_DATA_HOME
XDG_CACHE_HOME
XDG_STATE_HOME
```

Use appropriate standards-compliant fallbacks when variables are unset.

Do NOT hard-code:

```text
~/.config/betternotes
```

throughout the application.

Centralize path resolution.

---

# 27. Offline-First

The application must remain fully useful without Internet access.

Do not require:

* account
* remote server
* cloud service
* telemetry

No telemetry by default.

User data belongs to the user.

---

# 28. Import / Export

Eventually support:

* JSON
* Markdown
* plain text

Importers must validate input.

Do not silently discard unsupported or malformed data.

Exports should be understandable and portable where practical.

---

# 29. Backup / Recovery

Eventually provide functionality conceptually equivalent to:

```bash
betternotes backup
betternotes restore
```

Consider:

* atomic writes
* database corruption
* partial writes
* interrupted backups
* safe restore
* version compatibility

Never silently destroy existing user data during restore.

---

# 30. CLI

The GUI and CLI must share the same Rust application/domain core.

Do NOT duplicate business logic.

Target commands include:

```bash
betternotes new "Configure nginx"
betternotes list
betternotes search nginx
betternotes show 42
betternotes archive 42
betternotes backup
betternotes restore
```

---

# 31. Single Instance and IPC

The GUI should normally run as a single application instance.

Launching:

```bash
betternotes
```

while the application is already running should communicate with the existing instance instead of unnecessarily spawning another full instance.

CLI commands should be capable of communicating with the running application where appropriate.

IPC input must be treated as untrusted input.

Validate messages carefully.

---

# 32. Security

Treat as untrusted:

* imported files
* attachments
* IPC input
* note content
* filenames
* external paths

Avoid:

* command injection
* unsafe shell construction
* path traversal
* unintended file execution
* arbitrary code execution through note contents

Use safe filesystem APIs.

Never execute note contents.

---

# 33. Performance

The application should remain lightweight.

Avoid:

* unnecessary background workers
* constant polling
* excessive filesystem watchers
* unnecessary caches
* unnecessary async runtimes
* loading all note content when unnecessary

Use Tokio only when there is a concrete reason.

Measure before performing complicated optimization.

---

# 34. Rust ↔ Qt6/QML Integration

Before committing to a Rust/Qt integration library, evaluate currently maintained options.

Consider:

* maintenance activity
* Qt 6 support
* QML integration
* properties
* signals/slots
* model exposure
* threading
* build tooling
* packaging
* Linux compatibility
* documentation
* long-term maintainability

Document the selected approach and rationale.

Do not invent APIs from memory when uncertain.

Verify APIs against installed tooling or authoritative documentation where possible.

---

# 35. UI / UX

The QML interface should be:

* modern
* minimal
* polished
* responsive
* lightweight
* keyboard friendly
* mouse friendly
* touch-capable where practical
* accessible
* high-DPI aware

Themes:

* Light
* Dark
* System

Animations should be subtle.

Do not add animation merely for decoration.

Sticky note windows should remain visually simple and fast.

---

# 36. Packaging

Initial release targets:

1. Flatpak
2. AppImage

Possible later Linux packages:

* `.deb`
* `.rpm`
* Arch PKGBUILD

Windows/macOS packaging comes only after Linux v1.0 unless explicitly requested.

---

# 37. Open Source Repository

The project should eventually contain:

* LICENSE
* README.md
* CONTRIBUTING.md
* SECURITY.md
* CHANGELOG.md

Preferred license:

* MIT

or:

* Apache-2.0

Do not choose a final license without explicit project decision if one has not already been selected.

Documentation should eventually cover:

* building
* dependencies
* architecture
* packaging
* supported desktops
* Wayland limitations
* X11 behavior
* development workflow

---

# 38. Testing

Important Rust functionality requires tests.

Test areas include:

* note CRUD
* database migrations
* FTS5 search
* tags
* reminders
* serialization
* import/export
* backup/restore
* platform abstraction behavior where practical

Use integration tests where they provide meaningful coverage.

Do not rely exclusively on UI tests.

---

# 39. Development Phases

## Phase 1 — Foundation

Implement only:

* Rust workspace
* Qt6/QML integration
* minimal application executable
* basic application window
* initial QML architecture
* build system
* Linux development instructions
* basic logging/error handling where justified

Success criteria:

```bash
cargo build
```

works and the application can launch a Qt6/QML window.

Do NOT implement the feature set of later phases during Phase 1.

---

## Phase 2 — Basic Notes

Implement:

* SQLite
* migrations
* note model
* create
* edit
* delete
* autosave
* persistence

---

## Phase 3 — Sticky Windows

Implement:

* independent note windows
* multiple notes
* move
* resize
* collapse
* window state persistence

Respect Wayland limitations.

---

## Phase 4 — Modern UI

Implement:

* themes
* polished QML components
* high-DPI behavior
* responsive layouts
* appropriate animations

---

## Phase 5 — Search and Organization

Implement:

* FTS5
* tags
* priorities
* archive
* command palette
* global search

---

## Phase 6 — Linux Integration

Implement:

* system tray
* XDG autostart
* startup preference
* desktop notifications
* global shortcuts
* clipboard integration

---

## Phase 7 — Wayland / X11

Test and improve behavior across:

* KDE Plasma
* GNOME
* XFCE
* Hyprland
* Sway

Document unavoidable limitations.

---

## Phase 8 — Productivity

Implement:

* reminders
* recurring reminders
* Quick Capture
* attachments
* import/export
* backup/restore

---

## Phase 9 — CLI and IPC

Implement:

* CLI
* local IPC
* single-instance handling
* communication between CLI and running GUI

---

## Phase 10 — Linux Release

Prepare:

* Flatpak
* AppImage
* documentation
* screenshots
* CI
* release notes

Target:

Linux v1.0.

Only after Phase 10 should Windows and macOS become active development targets unless explicitly requested otherwise.

---

# 40. Development Phase Discipline

When asked to implement a specific phase:

ONLY implement that phase and required prerequisites.

Do not opportunistically implement features from future phases.

Example:

If asked for Phase 1, do not also add:

* SQLite note storage
* reminders
* attachments
* tray
* global shortcuts
* IPC
* FTS5

Those belong to later phases.

Small foundational interfaces are acceptable only when they clearly reduce future rework without introducing unnecessary complexity.

---

# 41. Build and Validation

After relevant modifications, run appropriate commands such as:

```bash
cargo fmt --check
cargo check
cargo test
cargo build
```

Run only commands appropriate to the current repository state.

For Qt/QML integration, also perform the appropriate Qt/CMake validation if the selected integration requires it.

Do not claim:

> Build successful

unless the build command actually succeeded.

Do not claim:

> Tests pass

unless tests actually ran successfully.

If local environment dependencies prevent validation, clearly report:

* command attempted
* error
* missing dependency
* expected resolution

Do not fake successful validation.

---

# 42. Research and API Accuracy

For rapidly changing libraries, Qt bindings, Wayland protocols, packaging tooling, or Linux APIs:

Do not rely blindly on remembered APIs.

Verify the current API before implementing when possible.

Prefer:

1. official documentation
2. upstream repository documentation
3. maintained examples
4. source code when necessary

Do not invent crate functions, Qt APIs, QML types, DBus APIs, or Wayland protocols.

---

# 43. Error Handling

Do not use panic-driven error handling for expected runtime failures.

Provide meaningful errors for:

* database failures
* filesystem failures
* invalid imports
* IPC failures
* missing optional desktop functionality

Optional desktop integration failure should degrade gracefully whenever possible.

Core data integrity failures should be surfaced clearly.

---

# 44. Future Cross-Platform Support

Windows and macOS are future targets.

Architecture should make future ports reasonable, but do NOT build speculative Windows/macOS implementations today.

Keep portable logic inside the Rust core.

Keep OS-specific behavior behind platform interfaces.

Linux quality has priority until Linux v1.0.

---

# 45. Naming

`BetterNotes` is currently a placeholder/project codename.

Do not assume it is the final public product name.

Before choosing a final name, check for conflicts with:

* GitHub projects
* Linux packages
* Flatpak/Flathub applications
* domains where relevant
* existing commercial applications

Do not use `LNotes` as the final project name because similarly named projects already exist.

---

# 46. Critical Agent Rules

Always follow these rules:

1. Inspect before editing.
2. Understand existing code before replacing it.
3. Keep changes focused.
4. Keep the project buildable.
5. Do not fake APIs.
6. Do not fake successful builds/tests.
7. Do not hide known limitations.
8. Do not assume Wayland behaves like X11.
9. Do not assume all desktop environments behave identically.
10. Prefer standards before compositor-specific hacks.
11. Protect user data.
12. Avoid unnecessary dependencies.
13. Avoid unnecessary async.
14. Avoid over-engineering.
15. Keep platform-specific code isolated.
16. Do not implement future phases without instruction.
17. Do not implement Windows/macOS before requested.
18. Document significant architectural decisions.
19. Run appropriate validation after changes.
20. Stop after completing the requested task.

# 47. Git and GitHub Workflow

Git is part of the development workflow.

For every development phase, follow this process.

## Before Starting a Phase

Before making changes:

1. Inspect the current Git status.
2. Identify the current branch.
3. Verify that the working tree does not contain unexpected changes.
4. Inspect the configured Git remote.
5. Do NOT discard, overwrite, reset, or modify unrelated user changes.
6. Pull/rebase only when it is safe and necessary.
7. Never use destructive Git commands such as `git reset --hard` unless explicitly instructed.

## During Development

Make changes only for the requested phase.

Do not commit temporary files, build artifacts, secrets, credentials, API keys, IDE caches, or machine-specific files.

Maintain an appropriate `.gitignore`.

Before committing, inspect:

```bash
git status
git diff
```

Make sure the commit contains only intentional project changes.

## Phase Completion

A phase is considered complete only after:

1. The requested implementation is finished.
2. Formatting has been checked.
3. Relevant tests have been executed.
4. The project has been built successfully where the environment permits.
5. Known failures or limitations have been documented.
6. `git status` and the final diff have been reviewed.

If validation fails because of a code problem introduced during the phase, fix it before committing.

If validation cannot run because of an external environment/dependency problem, document the exact problem before deciding whether the phase can reasonably be committed.

Do not falsely report successful tests or builds.

## Commit

After successfully completing a phase, create a Git commit.

Use Conventional Commit-style messages.

Preferred phase commit format:

```text
feat: complete phase <N> <short description>
```

Examples:

```text
feat: complete phase 1 foundation
feat: complete phase 2 basic notes
feat: complete phase 3 sticky windows
feat: complete phase 4 modern ui
feat: complete phase 5 search and organization
feat: complete phase 6 linux integration
feat: complete phase 7 wayland and x11 support
feat: complete phase 8 productivity features
feat: complete phase 9 cli and ipc
feat: complete phase 10 linux release
```

Before committing, review staged files:

```bash
git status
git diff --staged
```

Do not include unrelated user changes in the commit.

## GitHub Push

After the phase commit is successfully created, push it to the configured GitHub remote.

Use the existing remote and current development branch.

For example:

```bash
git push
```

If upstream tracking has not yet been configured, inspect the current branch and remote first, then configure the appropriate upstream safely.

Do NOT:

* force push
* rewrite published history
* delete remote branches
* modify repository visibility
* modify GitHub repository settings
* create or expose credentials
* print authentication tokens
* bypass authentication failures

unless explicitly instructed.

Never use:

```bash
git push --force
```

or:

```bash
git push --force-with-lease
```

as part of the normal phase workflow.

## Push Failure

If the push fails:

1. Read the Git error.
2. Determine whether the cause is authentication, network access, remote configuration, upstream configuration, or a remote conflict.
3. Fix only issues that can be resolved safely.
4. Never overwrite remote history to solve a conflict.
5. If user authentication or intervention is required, stop and report the exact command/error.

Do not claim the phase was pushed unless `git push` actually succeeded.

## Important Rule

Every successfully completed development phase should end with:

```text
implement
→ format
→ test
→ build
→ inspect diff
→ commit
→ push
→ report
```

After pushing, report:

* phase completed
* tests executed
* build result
* commit hash
* commit message
* branch
* remote push result

Then STOP.

Do not automatically begin the next phase.
