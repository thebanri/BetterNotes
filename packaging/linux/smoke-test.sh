#!/usr/bin/env bash
# Starts an installed BetterNotes without a display and checks that the whole
# interface loads: every QML module, the app's own types and the platform
# plugin. A package that installs but lacks a runtime dependency fails here.
#
#   packaging/linux/smoke-test.sh [command...]     (default: betternotes)
set -euo pipefail
command=("${@:-betternotes}")
home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT

# A throwaway profile, so the test never touches real notes.
export HOME="$home" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config"
export XDG_RUNTIME_DIR="$home/run" XDG_CURRENT_DESKTOP=smoke-test
# No session bus: the test must not put an icon in someone's tray or claim the
# app's bus name while a real instance runs.
export DBUS_SESSION_BUS_ADDRESS="unix:path=$home/no-session-bus"
mkdir -p -m 700 "$XDG_RUNTIME_DIR"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software

"${command[@]}" --version
log="$home/app.log"
set +e
timeout 15 "${command[@]}" --background > "$log" 2>&1
status=$?
set -e
cat "$log"
# The app keeps running until stopped, so the timeout is the expected end.
if [ "$status" -ne 124 ]; then
    echo "smoke test: the app exited with status $status" >&2
    exit 1
fi
if ! grep -q "application window loaded" "$log"; then
    echo "smoke test: the interface did not load" >&2
    exit 1
fi
if grep -qiE "is not installed|module .* not found|could not load the qt platform plugin|failed to load component" "$log"; then
    echo "smoke test: a runtime dependency is missing" >&2
    exit 1
fi
echo "smoke test: passed"
