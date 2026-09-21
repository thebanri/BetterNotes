#!/usr/bin/env bash
# Builds the Debian package from the working tree.
#
#   packaging/linux/deb/build-deb.sh [output-dir]
#
# Run it on the release the package is for: the app needs Qt 6.5 or newer,
# so Debian 13 (trixie) or Ubuntu 25.04 and later. Needs the build
# dependencies listed in .github/workflows/packages.yml and dpkg-dev.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
out="$(realpath -m "${1:-$root/dist}")"
version="$("$root/packaging/linux/version.sh")"
arch="$(dpkg --print-architecture)"
work="$root/target/pkg-deb"
pkg="$work/betternotes_${version}_${arch}"

cd "$root"
cargo build --release --locked -p betternotes

rm -rf "$work"
mkdir -p "$pkg/DEBIAN" "$out"
"$root/packaging/linux/stage.sh" "$pkg"
strip --strip-unneeded "$pkg/usr/bin/betternotes"
install -Dm644 "$root/LICENSE" "$pkg/usr/share/doc/betternotes/copyright"

# Shared-library dependencies, worked out the way debhelper does it.
# dpkg-shlibdeps insists on a debian/control naming the package.
mkdir -p "$work/debian"
printf 'Source: betternotes\n\nPackage: betternotes\nArchitecture: any\n' > "$work/debian/control"
libraries="$(cd "$work" && dpkg-shlibdeps -O "$pkg/usr/bin/betternotes" | sed -n 's/^shlibs:Depends=//p')"

# QML modules are loaded at run time, so nothing links against them and they
# have to be listed. The platform plugins are loaded the same way.
runtime=(
    qml6-module-qtqml
    qml6-module-qtqml-models
    qml6-module-qtqml-workerscript
    qml6-module-qtquick
    qml6-module-qtquick-window
    qml6-module-qtquick-layouts
    qml6-module-qtquick-templates
    qml6-module-qtquick-controls
    qml6-module-qtquick-dialogs
    qml6-module-qtquick-shapes
    qml6-module-qt-labs-platform
    qml6-module-qt-labs-folderlistmodel
    qt6-qpa-plugins
    qt6-wayland
)
depends="$libraries$(printf ', %s' "${runtime[@]}")"

cat > "$pkg/DEBIAN/control" <<CONTROL
Package: betternotes
Version: $version
Architecture: $arch
Maintainer: BetterNotes Contributors <https://github.com/thebanri/BetterNotes/issues>
Installed-Size: $(du -sk "$pkg/usr" | cut -f1)
Depends: $depends
Section: utils
Priority: optional
Homepage: https://github.com/thebanri/BetterNotes
Description: Sticky notes for the Linux desktop
 BetterNotes keeps notes as independent sticky windows on the desktop, with
 rich text, links, tags, full-text search, reminders, and a library window
 for finding and organising them. Notes are stored locally in SQLite.
CONTROL

dpkg-deb --root-owner-group --build "$pkg" "$out/"
ls -1 "$out/betternotes_${version}_${arch}.deb"
