#!/usr/bin/env bash
# Lays out a built BetterNotes under a staging root exactly as it installs
# under /usr. Every package format installs from this one layout.
#
#   packaging/linux/stage.sh <destdir> [binary]
#
# The binary defaults to the release build in CARGO_TARGET_DIR (or target/).
# Licence files are left to
# each format, since every distribution keeps them somewhere else.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dest="${1:?usage: stage.sh <destdir> [binary]}"
binary="${2:-${CARGO_TARGET_DIR:-$root/target}/release/betternotes}"
id=org.betternotes.BetterNotes

install -Dm755 "$binary" "$dest/usr/bin/betternotes"
install -Dm644 "$root/packaging/linux/$id.desktop" "$dest/usr/share/applications/$id.desktop"
install -Dm644 "$root/packaging/linux/$id.metainfo.xml" "$dest/usr/share/metainfo/$id.metainfo.xml"
install -Dm644 "$root/assets/icons/$id.svg" "$dest/usr/share/icons/hicolor/scalable/apps/$id.svg"
for size in 16 22 24 32 48 64 128 256; do
    install -Dm644 "$root/assets/icons/hicolor/$id-$size.png" \
        "$dest/usr/share/icons/hicolor/${size}x${size}/apps/$id.png"
done
