# Building BetterNotes with Flatpak

BetterNotes can be built into a sandboxed Flatpak package using `flatpak-builder`.

## Prerequisites

Ensure `flatpak` and `flatpak-builder` are installed on your Linux distribution:

```bash
# Arch Linux / CachyOS
sudo pacman -S flatpak flatpak-builder

# Fedora
sudo dnf install flatpak flatpak-builder

# Ubuntu / Debian
sudo apt install flatpak flatpak-builder
```

Install the required KDE Qt 6 runtime and Rust SDK extension:

```bash
flatpak install flathub org.kde.Platform//6.7 org.kde.Sdk//6.7 org.freedesktop.Sdk.Extension.rust-stable//24.08
```

## Build and Install

From the repository root:

```bash
# Build and install locally to user directory
flatpak-builder --user --install --force-clean build-dir packaging/linux/flatpak/org.betternotes.BetterNotes.yaml

# Run the installed Flatpak
flatpak run org.betternotes.BetterNotes
```

## Creating a Flatpak Bundle (.flatpak)

To generate a single-file distributable `.flatpak` bundle:

```bash
flatpak-builder --repo=repo --force-clean build-dir packaging/linux/flatpak/org.betternotes.BetterNotes.yaml
flatpak build-bundle repo BetterNotes.flatpak org.betternotes.BetterNotes
```
