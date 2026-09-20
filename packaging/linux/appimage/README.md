# Building BetterNotes AppImage

The AppImage format provides a single-file executable that runs on any modern Linux distribution without installation.

## Build Requirements

- Rust 1.88+ toolchain
- GCC / Clang (C++17)
- Qt 6 libraries and tools
- `appimagetool` (optional, for packing the AppDir into `.AppImage`)

## Generating the AppImage

Run the build script from the repository root:

```bash
./packaging/linux/appimage/build-appimage.sh
```

This will:
1. Compile the optimized release binary (`target/release/betternotes`).
2. Construct the standardized Freedesktop `AppDir` with desktop files, scalable icons, and AppRun script.
3. If `appimagetool` is installed, package the directory into `target/BetterNotes-x86_64.AppImage`.
