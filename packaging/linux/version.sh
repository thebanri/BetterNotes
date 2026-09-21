#!/usr/bin/env bash
# Prints the application version, which Cargo.toml owns for every package.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sed -n '/^\[workspace\.package\]/,/^\[/ s/^version *= *"\([^"]*\)".*/\1/p' "$root/Cargo.toml"
