#!/usr/bin/env bash
# Writes a source tarball of the working tree, unpacking to BetterNotes-<ver>/
# like GitHub's tag archives, so local and CI builds use the release recipes.
#
# Only files git tracks are included, as they are on disk (uncommitted edits
# too). Untracked files never are: the app's own exports land in the working
# directory, and a user's notes must not end up inside a package. Stage a new
# file with `git add -N` to include it before its first commit.
#
#   packaging/linux/source-tarball.sh <output.tar.gz>
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output="$(realpath -m "${1:?usage: source-tarball.sh <output.tar.gz>}")"
version="$("$root/packaging/linux/version.sh")"
cd "$root"
git ls-files -z --cached |
    while IFS= read -r -d '' file; do [ -e "$file" ] && printf '%s\0' "$file"; done |
    tar --null --files-from=- --transform "s,^,BetterNotes-$version/," -czf "$output"
