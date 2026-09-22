#!/usr/bin/env bash
# Builds LayerShellQt, which lets sticky notes be desktop widgets on Wayland
# (see app/src/desktop_widgets.h), for a Qt that does not come with it: the
# Qt bundled into the AppImage.
#
#   packaging/linux/build-layer-shell-qt.sh [prefix]
#
# QMAKE selects the Qt (default: qmake6 on the PATH), which must be 6.8 or
# newer and include Qt Wayland. LayerShellQt uses Qt's private Wayland API, so
# it has to be built against exactly the Qt the app ships with. The prefix
# defaults to that Qt's own, where the app's build finds it without help;
# elsewhere, point BETTERNOTES_LAYER_SHELL_PREFIX at it.
#
# Needs cmake, a C++ compiler, wayland-scanner and the wayland and xkbcommon
# development files. wayland-protocols is fetched when pkg-config lacks it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export QMAKE="${QMAKE:-$(command -v qmake6 || command -v qmake)}"
qt="$("$QMAKE" -query QT_INSTALL_PREFIX)"
prefix="$(realpath -m "${1:-$qt}")"
work="$root/target/layer-shell-qt"
mkdir -p "$work"
cd "$work"

fetch() { # url sha256
    local file
    file="$(basename "$1")"
    [ -f "$file" ] || curl -fsSL --retry 3 -o "$file" "$1"
    echo "$2  $file" | sha256sum -c --quiet -
    rm -rf "${file%.tar.xz}"
    tar -xf "$file"
}

fetch https://download.kde.org/stable/frameworks/6.14/extra-cmake-modules-6.14.0.tar.xz \
    d02cbbb3269b39680884abf6f14ba68f448570c554173f5249da3b8761784c13
fetch https://download.kde.org/stable/plasma/6.4.5/layer-shell-qt-6.4.5.tar.xz \
    ef6baae22114f038af89029f3f0075ee29c3b91fd49100828c4c3a32e1496e95

if ! pkg-config --exists wayland-protocols; then
    fetch https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/1.45/downloads/wayland-protocols-1.45.tar.xz \
        4d2b2a9e3e099d017dc8107bf1c334d27bb87d9e4aff19a0c8d856d17cd41ef0
    # The source tree has the installed layout (stable/xdg-shell/...), so a
    # pkg-config file pointing at it is all the build needs.
    mkdir -p pkgconfig
    printf 'pkgdatadir=%s\nName: Wayland Protocols\nDescription: Wayland protocol files\nVersion: 1.45\n' \
        "$work/wayland-protocols-1.45" > pkgconfig/wayland-protocols.pc
    export PKG_CONFIG_PATH="$work/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi

cmake -S extra-cmake-modules-6.14.0 -B build-ecm -DCMAKE_INSTALL_PREFIX="$work/ecm" \
    -DBUILD_TESTING=OFF -DBUILD_HTML_DOCS=OFF -DBUILD_MAN_DOCS=OFF -DBUILD_QTHELP_DOCS=OFF
cmake --install build-ecm

cmake -S layer-shell-qt-6.4.5 -B build-lsq -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$qt;$work/ecm" -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_TESTING=OFF
cmake --build build-lsq --parallel
cmake --install build-lsq
