#!/usr/bin/env bash
# Builds a portable AppImage: the app plus the Qt libraries, QML modules and
# X11/Wayland platform plugins it needs, bundled by linuxdeploy and its Qt
# plugin.
#
#   packaging/linux/appimage/build-appimage.sh [output-dir]
#
# QMAKE selects the Qt to bundle (default: qmake6 on the PATH); it must be
# Qt 6.5 or newer. An AppImage runs where glibc is at least as new as on the
# build machine, so build on the oldest distribution you want to support.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
out="$(realpath -m "${1:-$root/dist}")"
version="$("$root/packaging/linux/version.sh")"
arch="$(uname -m)"
work="$root/target/pkg-appimage"
appdir="$work/AppDir"
tools="$root/target/appimage-tools"
id=org.betternotes.BetterNotes

export QMAKE="${QMAKE:-$(command -v qmake6 || command -v qmake)}"
cd "$root"
cargo build --release --locked -p betternotes

rm -rf "$work"
mkdir -p "$work" "$out" "$tools"
"$root/packaging/linux/stage.sh" "$appdir"

fetch() {
    [ -x "$tools/$1" ] && return
    curl -fsSL --retry 3 -o "$tools/$1" "$2"
    chmod +x "$tools/$1"
}
fetch "linuxdeploy-$arch.AppImage" \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$arch.AppImage"
fetch "linuxdeploy-plugin-qt-$arch.AppImage" \
    "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-$arch.AppImage"

# Build machines often lack FUSE; the tools can unpack themselves instead.
export APPIMAGE_EXTRACT_AND_RUN=1
# linuxdeploy's bundled strip predates newer ELF sections (.relr.dyn) and
# fails the whole build on current system libraries. Stripping is optional.
export NO_STRIP=1
# Bundle every QML module the sources import.
export QML_SOURCES_PATHS="$root/qml"
# xcb is always bundled; Wayland needs asking for. Qt 6.10 merged the Wayland
# platform plugins into libqwayland.so; older releases ship -egl and -generic.
platforms="$("$QMAKE" -query QT_INSTALL_PLUGINS)/platforms"
wayland=()
for plugin in libqwayland.so libqwayland-egl.so libqwayland-generic.so; do
    [ -e "$platforms/$plugin" ] && wayland+=("$plugin")
done
if [ "${#wayland[@]}" -eq 0 ]; then
    echo "No Wayland platform plugin in $platforms; install Qt's Wayland support." >&2
    exit 1
fi
# offscreen is tiny and lets the same smoke test run the AppImage headless.
export EXTRA_PLATFORM_PLUGINS="$(IFS=';'; echo "${wayland[*]}");libqoffscreen.so"
export EXTRA_QT_MODULES="waylandclient"
output="$out/BetterNotes-$version-$arch.AppImage"
export LDAI_OUTPUT="$output" OUTPUT="$output"

# linuxdeploy follows ldd, so resolve Qt from the same installation as QMAKE;
# otherwise a system Qt could be bundled next to another Qt's plugins.
export LD_LIBRARY_PATH="$("$QMAKE" -query QT_INSTALL_LIBS)${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [ -d "$tools/jxrlib/usr/lib" ]; then
    export LD_LIBRARY_PATH="$tools/jxrlib/usr/lib:$LD_LIBRARY_PATH"
fi

cd "$work"
"$tools/linuxdeploy-$arch.AppImage" \
    --appdir "$appdir" \
    --desktop-file "$appdir/usr/share/applications/$id.desktop" \
    --icon-file "$appdir/usr/share/icons/hicolor/scalable/apps/$id.svg" \
    --plugin qt

# The Qt plugin leaves out the client buffer integrations, and without them
# Qt Quick cannot create an OpenGL context on Wayland ("Failed to load client
# buffer integration: wayland-egl"). Add them and their libraries by hand.
integrations="$("$QMAKE" -query QT_INSTALL_PLUGINS)/wayland-graphics-integration-client"
if [ -d "$integrations" ]; then
    mkdir -p "$appdir/usr/plugins"
    cp -r "$integrations" "$appdir/usr/plugins/"
    # Some Qt builds keep compositor-side integrations here too; a client
    # needs none of them.
    rm -f "$appdir/usr/plugins/wayland-graphics-integration-client/"*-server.so
fi
"$tools/linuxdeploy-$arch.AppImage" \
    --appdir "$appdir" \
    --deploy-deps-only "$appdir/usr/plugins/wayland-graphics-integration-client" \
    --output appimage
ls -1 "$output"
