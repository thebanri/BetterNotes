#!/bin/sh
# Installs or updates BetterNotes for the current user from the latest GitHub
# release, without root:
#
#   curl -fsSL https://raw.githubusercontent.com/thebanri/BetterNotes/main/install.sh | sh
#
# and removes it again (notes are kept):
#
#   curl -fsSL https://raw.githubusercontent.com/thebanri/BetterNotes/main/install.sh | sh -s -- --uninstall
#
# The AppImage goes to ~/.local/opt/betternotes, `betternotes` on the PATH is
# a link to it in ~/.local/bin, and the app itself adds its menu entry and
# icons (`betternotes install`). The download is checked against the
# release's SHA256SUMS before anything is replaced.
set -eu

repo=thebanri/BetterNotes
dir="$HOME/.local/opt/betternotes"
appimage="$dir/BetterNotes-x86_64.AppImage"
link="$HOME/.local/bin/betternotes"

say() { printf '%s\n' "$*"; }
fail() {
    printf 'BetterNotes installer: %s\n' "$*" >&2
    exit 1
}

[ -n "${HOME:-}" ] || fail "HOME is not set."
[ "$(id -u)" -ne 0 ] || fail "run this as your own user, not root; it installs for you only."
[ "$(uname -s)" = Linux ] || fail "BetterNotes currently supports Linux only."
case "$(uname -m)" in
x86_64 | amd64) ;;
*) fail "releases are built for x86_64 only; see the README to build from source." ;;
esac

# Runs the installed AppImage even where FUSE is missing.
run_appimage() {
    if command -v fusermount >/dev/null 2>&1 || command -v fusermount3 >/dev/null 2>&1; then
        APPIMAGE="$appimage" "$appimage" "$@"
    else
        APPIMAGE="$appimage" APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" "$@"
    fi
}

if [ "${1:-}" = "--uninstall" ]; then
    if [ -x "$appimage" ]; then
        run_appimage uninstall || true
    fi
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$appimage" ]; then
        rm -f "$link"
    fi
    rm -f "$appimage"
    rmdir "$dir" 2>/dev/null || true
    say "BetterNotes was removed. Your notes are kept in ${XDG_DATA_HOME:-$HOME/.local/share}/betternotes."
    exit 0
fi

command -v curl >/dev/null 2>&1 || fail "curl is required."
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum (coreutils) is required."

say "Looking up the latest BetterNotes release..."
release="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest")" ||
    fail "could not reach GitHub."
asset_url() {
    printf '%s\n' "$release" |
        grep -o "\"browser_download_url\": *\"[^\"]*$1\"" |
        head -n 1 |
        sed 's/.*"\(https:[^"]*\)"$/\1/'
}
url="$(asset_url '-x86_64\.AppImage')"
sums_url="$(asset_url '/SHA256SUMS')"
[ -n "$url" ] || fail "the latest release has no x86_64 AppImage."
[ -n "$sums_url" ] || fail "the latest release has no SHA256SUMS."
name="${url##*/}"

mkdir -p "$dir" "$(dirname "$link")"
# Download beside the target so the final move replaces it in one step.
work="$(mktemp -d "$dir/.download.XXXXXX")"
trap 'rm -rf "$work"' EXIT INT TERM

say "Downloading $name..."
curl -fL --progress-bar -o "$work/$name" "$url" || fail "the download failed."
curl -fsSL -o "$work/SHA256SUMS" "$sums_url" || fail "could not download SHA256SUMS."
grep -F "  $name" "$work/SHA256SUMS" >"$work/expected" || fail "SHA256SUMS does not list $name."
(cd "$work" && sha256sum --check --status expected) ||
    fail "the checksum does not match; the download was discarded."

chmod 755 "$work/$name"
mv -f "$work/$name" "$appimage"
ln -sfn "$appimage" "$link"

run_appimage install || fail "the menu entry could not be added; run '$appimage install' to see why."

if ! command -v fusermount >/dev/null 2>&1 && ! command -v fusermount3 >/dev/null 2>&1; then
    say "Note: FUSE is not installed, so launching from the menu may fail."
    say "Install your distribution's fuse package, or start it with APPIMAGE_EXTRACT_AND_RUN=1."
fi
case ":$PATH:" in
*":$HOME/.local/bin:"*) ;;
*) say "Note: $HOME/.local/bin is not on your PATH; add it to run 'betternotes' from a terminal." ;;
esac
version="${name#BetterNotes-}"
say "BetterNotes ${version%-x86_64.AppImage} is installed. Start it from your applications menu or run 'betternotes'."
