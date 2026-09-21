#!/usr/bin/env bash
# Refreshes the translation sources from the QML and rebuilds the compiled
# translations the app embeds:
#
#   translations/update.sh
#
# Translate new texts in translations/qml_<lang>.ts (Qt Linguist, or by
# hand), then run this again. qml_en.ts only holds English plural forms.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bin="$(qmake6 -query QT_INSTALL_BINS 2>/dev/null || echo /usr/lib/qt6/bin)"
cd "$root"
"$bin/lupdate" qml -extensions qml,js -ts translations/qml_tr.ts translations/qml_en.ts
for lang in tr en; do
    "$bin/lrelease" "translations/qml_$lang.ts" -qm "qml/windows/i18n/qml_$lang.qm"
done
