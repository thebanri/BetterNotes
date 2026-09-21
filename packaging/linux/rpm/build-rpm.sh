#!/usr/bin/env bash
# Builds the RPM package from the working tree with rpmbuild.
#
#   packaging/linux/rpm/build-rpm.sh [output-dir]
#
# Run it on the Fedora release the package is for, with rpm-build and the
# spec's BuildRequires installed (dnf builddep packaging/linux/rpm/betternotes.spec).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
out="$(realpath -m "${1:-$root/dist}")"
version="$("$root/packaging/linux/version.sh")"
work="$root/target/pkg-rpm"

rm -rf "$work"
mkdir -p "$work/SOURCES" "$out"
"$root/packaging/linux/source-tarball.sh" "$work/SOURCES/betternotes-$version.tar.gz"
rpmbuild -bb \
    --define "_topdir $work" \
    --define "pkg_version $version" \
    "$root/packaging/linux/rpm/betternotes.spec"
find "$work/RPMS" -name "betternotes-$version-*.rpm" -exec cp {} "$out/" \;
ls -1 "$out"/betternotes-"$version"-*.rpm
