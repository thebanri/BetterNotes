# Linux packaging validation

Updated: 2026-09-21. Current package version: **0.1.0 (preview)**.

The earlier report incorrectly named a separate `release.yml`, an older Flatpak
runtime and a completed v1.0 release. The actual publishing workflow is
[packages.yml](../.github/workflows/packages.yml), and the Flatpak manifest uses
KDE runtime 6.9. Historical phase completion claims do not prove release readiness.

## Existing package evidence

[Packages run 35585794709](https://github.com/thebanri/BetterNotes/actions/runs/35585794709)
completed successfully for commit `76d91ad162e901b44bd8a9eb0f04cd8dc4953911`:

- Debian package built and installed on Debian trixie and Ubuntu rolling;
  both headless smoke tests passed.
- Fedora RPM built, installed and passed its headless smoke test.
- Arch package built, installed and passed its headless smoke test.
- AppImage built on Ubuntu 22.04 and passed its headless smoke test on Ubuntu 24.04.
- Flatpak bundle built successfully.

That run was manually dispatched on `main`. The GitHub Release job was **skipped**
because no version tag was being built. These results apply to that commit, not
automatically to subsequent changes.

## Release workflow changes

The workflow now validates the version before packaging and calls the shared
CI workflow, making formatting, Clippy, tests and a release build prerequisites
for publishing. It includes release notes, a committed-source archive and verified
SHA-256 checksums, rejects missing assets and marks `0.x` versions as prereleases.
See [the release procedure](releasing.md) for the tag and publishing steps.

## Local validation of the release changes

On CachyOS with Rust 1.98.1 and Qt 6.11.2:

- `cargo fmt --check`, `cargo check --locked` and
  `cargo clippy --all-targets --all-features --locked -- -D warnings` passed.
- `cargo test --locked` passed all 62 Rust tests and the Qt/QML integration
  executable. The first sandboxed attempt could not bind an IPC socket
  (`Operation not permitted`); the successful rerun allowed local sockets and
  used an unavailable session-bus address to avoid desktop notifications.
- `cargo build --release --locked` passed. System Qt/C++ headers emit a
  `QChar` SFINAE warning with the installed compiler; it is not a build failure.
- `actionlint` 1.7.12 passed both workflow files.
- Local workflow-step checks accepted the matching tag, rejected mismatches,
  verified all six asset checksums, detected corruption and missing package
  formats, and confirmed the source archive excludes untracked files.
- Relative documentation links and `git diff --check` passed.

This validates local code and workflow logic; it does not claim a new GitHub
Release was published or that all distro packages were rebuilt locally.

## Remaining coverage

Flatpak GUI startup and sandbox integration require manual validation. Headless
checks do not certify real Wayland/X11 behavior, notification delivery, tray
availability, window placement or multi-monitor recovery. No complete desktop
compatibility matrix or Linux v1.0 certification is claimed here.
