# Linux packaging

All formats install the same files, laid out by `stage.sh`:

```
/usr/bin/betternotes
/usr/share/applications/org.betternotes.BetterNotes.desktop
/usr/share/metainfo/org.betternotes.BetterNotes.metainfo.xml
/usr/share/icons/hicolor/scalable/apps/org.betternotes.BetterNotes.svg
/usr/share/icons/hicolor/<size>x<size>/apps/org.betternotes.BetterNotes.png
```

The version comes from `Cargo.toml` (`version.sh`). Each build script writes
its package to `dist/` (or the directory given as its argument) and builds
from the working tree, so uncommitted changes are included. Source tarballs
contain only files git tracks (`source-tarball.sh`), never untracked files such
as the app's own exports.

`smoke-test.sh` starts an installed build headless, with a throwaway profile
and no session bus, and fails if any QML module or plugin is missing. CI runs
it against the native packages and AppImage on clean systems. Flatpak currently
has build coverage only; its GUI and sandbox integration need manual testing.

Pushing a `vMAJOR.MINOR.PATCH` tag matching `Cargo.toml` publishes a GitHub Release
after CI and package checks pass. All five formats, a source archive and
`SHA256SUMS` are attached, and it becomes the Latest release. A manual
workflow run on `main` uploads Actions artifacts but does not publish a release.

## Formats

| Script | Build on | Needs |
|---|---|---|
| `deb/build-deb.sh` | Debian 13 / Ubuntu 25.04+ | build dependencies in `.github/workflows/packages.yml`, `dpkg-dev` |
| `rpm/build-rpm.sh` | Fedora | `rpm-build` and the spec's `BuildRequires` |
| `arch/build-arch.sh` | Arch Linux | `base-devel`, `rust`, the PKGBUILD's `depends`; run as a regular user |
| `appimage/build-appimage.sh` | the oldest system to support | Qt 6.5+ (`QMAKE=/path/to/qmake`), network access for linuxdeploy |
| `flatpak/org.betternotes.BetterNotes.yaml` | anywhere | `flatpak-builder`, KDE runtime 6.9 |

Qt 6.5 is the minimum: older distributions (Debian 12, Ubuntu 24.04) cannot
build or run the app from system Qt; use the AppImage or Flatpak there.

## Desktop integration per format

On KDE Plasma the app keeps notes off the taskbar, below other windows, and
where they were left, through a KWin script it loads over D-Bus with `busctl`.
Notes shown as desktop widgets (layer-shell surfaces, see the main README)
need no script: the app places and stacks them itself.

Desktop widgets need LayerShellQt built for the Qt in use. Native packages
depend on the distribution's; the AppImage and Flatpak build it
([build-layer-shell-qt.sh](build-layer-shell-qt.sh) and the Flatpak manifest).

- `.deb`, `.rpm`, Arch, AppImage: full integration.
- **Flatpak: partly.** The sandbox has no `busctl`, so the KWin script is not
  loaded. With desktop widgets on (the default) that does not matter on
  Wayland: notes are layer-shell surfaces, off the taskbar and placed by the
  app. With them off, notes appear in the taskbar, stay ordinary windows and
  are placed by KWin. "Start at login" also writes inside the sandbox, where the desktop
  never reads it; it needs the Background portal instead. The tray icon
  registers without owning a well-known bus name there, which is untested.

## Flathub

The manifest lets cargo download crates during the build, which suits the
bundle published with each release. Flathub builds offline: submitting there
needs the crates listed as sources (`flatpak-cargo-generator.py`).
