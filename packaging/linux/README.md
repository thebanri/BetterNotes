# Linux packaging

All formats install the same files, laid out by `stage.sh`:

```
/usr/bin/betternotes
/usr/share/applications/org.betternotes.BetterNotes.desktop
/usr/share/metainfo/org.betternotes.BetterNotes.metainfo.xml
/usr/share/icons/hicolor/scalable/apps/org.betternotes.BetterNotes.svg
```

The version comes from `Cargo.toml` (`version.sh`). Each build script writes
its package to `dist/` (or the directory given as its argument) and builds
from the working tree, so uncommitted changes are included. Source tarballs
contain only files git tracks (`source-tarball.sh`), never untracked files such
as the app's own exports.

`smoke-test.sh` starts an installed build headless, with a throwaway profile
and no session bus, and fails if any QML module or plugin is missing. CI runs
it against every package on a clean system.

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

- `.deb`, `.rpm`, Arch, AppImage: full integration.
- **Flatpak: not yet.** The sandbox has no `busctl`, so the KWin script is not
  loaded: notes appear in the taskbar, stay ordinary windows and are placed by
  KWin. "Start at login" also writes inside the sandbox, where the desktop
  never reads it; it needs the Background portal instead.

## Flathub

The manifest lets cargo download crates during the build, which suits the
bundle published with each release. Flathub builds offline: submitting there
needs the crates listed as sources (`flatpak-cargo-generator.py`).
