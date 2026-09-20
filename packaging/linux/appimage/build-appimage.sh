#!/usr/bin/env bash
set -euo pipefail

# Build script to assemble an AppDir and build BetterNotes.AppImage
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_DIR="${ROOT_DIR}/target/appimage"
APPDIR="${BUILD_DIR}/AppDir"

echo "==> Building BetterNotes release binary..."
cd "${ROOT_DIR}"
cargo build --release --locked

echo "==> Preparing AppDir layout at ${APPDIR}..."
rm -rf "${BUILD_DIR}"
mkdir -p "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr/share/applications"
mkdir -p "${APPDIR}/usr/share/metainfo"
mkdir -p "${APPDIR}/usr/share/icons/hicolor/scalable/apps"

# Copy binary
cp "${ROOT_DIR}/target/release/betternotes" "${APPDIR}/usr/bin/betternotes"

# Copy desktop and metainfo metadata
cp "${ROOT_DIR}/packaging/linux/org.betternotes.BetterNotes.desktop" "${APPDIR}/usr/share/applications/"
cp "${ROOT_DIR}/packaging/linux/org.betternotes.BetterNotes.desktop" "${APPDIR}/"
cp "${ROOT_DIR}/packaging/linux/org.betternotes.BetterNotes.metainfo.xml" "${APPDIR}/usr/share/metainfo/"

# Copy icons
cp "${ROOT_DIR}/assets/icons/org.betternotes.BetterNotes.svg" "${APPDIR}/usr/share/icons/hicolor/scalable/apps/"
cp "${ROOT_DIR}/assets/icons/org.betternotes.BetterNotes.svg" "${APPDIR}/org.betternotes.BetterNotes.svg"
cp "${ROOT_DIR}/assets/icons/org.betternotes.BetterNotes.svg" "${APPDIR}/.DirIcon"

# Copy AppRun
cp "${ROOT_DIR}/packaging/linux/appimage/AppRun" "${APPDIR}/AppRun"
chmod +x "${APPDIR}/AppRun"

echo "==> AppDir successfully constructed at ${APPDIR}."

if command -v appimagetool >/dev/null 2>&1; then
    echo "==> Packaging with appimagetool..."
    ARCH="$(uname -m)" appimagetool "${APPDIR}" "${ROOT_DIR}/target/BetterNotes-${ARCH}.AppImage"
    echo "==> AppImage created: ${ROOT_DIR}/target/BetterNotes-${ARCH}.AppImage"
else
    echo "==> appimagetool not found in PATH."
    echo "    To generate the final .AppImage file, download appimagetool from https://github.com/AppImage/AppImageKit/releases"
    echo "    and run: appimagetool ${APPDIR} target/BetterNotes-x86_64.AppImage"
fi
