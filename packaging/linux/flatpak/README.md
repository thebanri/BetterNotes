# Flatpak

```bash
flatpak install --user flathub org.kde.Platform//6.9 org.kde.Sdk//6.9 \
    org.freedesktop.Sdk.Extension.rust-stable//24.08
flatpak-builder --user --install --force-clean build-dir \
    packaging/linux/flatpak/org.betternotes.BetterNotes.yaml
flatpak run org.betternotes.BetterNotes
```

A single-file bundle:

```bash
flatpak-builder --repo=repo --force-clean build-dir \
    packaging/linux/flatpak/org.betternotes.BetterNotes.yaml
flatpak build-bundle repo BetterNotes.flatpak org.betternotes.BetterNotes
```

Limitations of the sandboxed build (KDE integration, start at login) are
listed in [../README.md](../README.md#desktop-integration-per-format).
