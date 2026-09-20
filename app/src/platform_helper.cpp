#include "platform_helper.h"
#include <QGuiApplication>
#include <QClipboard>

void platformCopyToClipboard(const QString& text) {
    if (auto* app = qobject_cast<QGuiApplication*>(QCoreApplication::instance())) {
        if (auto* clipboard = app->clipboard()) {
            clipboard->setText(text);
        }
    }
}

QString platformGetClipboardText() {
    if (auto* app = qobject_cast<QGuiApplication*>(QCoreApplication::instance())) {
        if (auto* clipboard = app->clipboard()) {
            return clipboard->text();
        }
    }
    return QString();
}
