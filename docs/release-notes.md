BetterNotes is a Linux desktop sticky notes application built with Rust and Qt 6/QML.
This is a preview under a working project name.

This build includes independent sticky windows, autosave, rich text editing,
search, tags, themes, reminders, attachments, JSON/Markdown import and export,
backups, and a CLI. Notes remain on your machine without an account or cloud service.

## Downloads

All binary assets below target **x86_64 / amd64**:

| Asset | Use on |
| --- | --- |
| `.deb` | Debian 13 / compatible Ubuntu versions |
| `.rpm` | The Fedora release identified in the filename |
| `.pkg.tar.zst` | Arch Linux / compatible derivatives |
| `.AppImage` | Systems with glibc 2.35+ and compatible desktop libraries; Qt is bundled |
| `.flatpak` | Systems with Flatpak; the KDE runtime is downloaded during installation |
| `-source.tar.gz` | Source code from the tagged commit |

Download your package and `SHA256SUMS` into the same directory, then run
`sha256sum --check --ignore-missing SHA256SUMS`. Your package should report `OK`.
Checksums are provided; independent package signatures are not.

See the [installation instructions](https://github.com/thebanri/BetterNotes#install)
for commands and package selection.

## Known limitations

- Wayland positioning, stacking and activation depend on the compositor.
  KDE Plasma has optional KWin integration; generic Wayland support has fewer controls.
- Flatpak currently lacks KWin host integration and working host autostart.
  It is distributed here as a bundle, not through Flathub.
- Configure a desktop-wide Quick Capture shortcut yourself using
  `betternotes --quick-capture`; the built-in key binding is application-local.
- Reminders need the application running and a working notification service.
- CI checks native package and AppImage startup headlessly. The Flatpak bundle
  is built in CI; its GUI and sandbox integrations still need manual testing.
- ARM64 packages and Windows/macOS builds are not provided.

Back up your notes before changing builds. When reporting a desktop issue,
include your distribution, desktop session, package format and the output of
`betternotes --diagnostics`.
