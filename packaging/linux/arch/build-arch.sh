#!/usr/bin/env bash
# Builds the Arch Linux package from the working tree with makepkg.
#
#   packaging/linux/arch/build-arch.sh [output-dir]
#
# Needs base-devel, cargo and the PKGBUILD's dependencies installed; run as a
# regular user, as makepkg requires. Extra arguments for makepkg can be given
# in MAKEPKG_FLAGS (e.g. --nocheck).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
out="$(realpath -m "${1:-$root/dist}")"
version="$("$root/packaging/linux/version.sh")"
work="$root/target/pkg-arch"

rm -rf "$work"
mkdir -p "$work" "$out"
tarball="betternotes-$version.tar.gz"
"$root/packaging/linux/source-tarball.sh" "$work/$tarball"
sed "s/^pkgver=.*/pkgver=$version/" "$root/packaging/linux/arch/PKGBUILD" > "$work/PKGBUILD"
(cd "$work" && BETTERNOTES_SOURCE="$tarball" makepkg --force --cleanbuild ${MAKEPKG_FLAGS:-})
cp "$work"/betternotes-"$version"-*.pkg.tar.zst "$out/"
ls -1 "$out"/betternotes-"$version"-*.pkg.tar.zst
