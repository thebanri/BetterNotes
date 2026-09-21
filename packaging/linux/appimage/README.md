# AppImage

```bash
QMAKE=/path/to/Qt/6.8.3/gcc_64/bin/qmake packaging/linux/appimage/build-appimage.sh
```

Bundles the app with Qt, the QML modules it imports and the X11 and Wayland
platform plugins, using linuxdeploy and linuxdeploy-plugin-qt (downloaded into
`target/appimage-tools/` on first use). `QMAKE` picks the Qt to bundle and
defaults to `qmake6` on the PATH.

An AppImage runs on systems whose glibc is at least as new as the build
machine's. Releases are built on Ubuntu 22.04 with Qt 6.8 from the Qt
installer, so they run on distributions from 2022 onwards. A build against a
distribution's own Qt can pull in that distribution's extra Qt plugins, which
is why releases use the upstream Qt.

Run without FUSE with `APPIMAGE_EXTRACT_AND_RUN=1`.
