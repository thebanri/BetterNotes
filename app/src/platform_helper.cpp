#include "platform_helper.h"
#include <QGuiApplication>
#include <QClipboard>
#include <QCursor>
#include <QIcon>
#include <QStandardPaths>
#include <QUrl>
#include <QtWidgets/QApplication>
#include "cxx-qt-lib/qguiapplication.h"
#include "cxx-qt-lib/qcoreapplication.h"

namespace rust {
namespace cxxqtlib1 {

::std::unique_ptr<QGuiApplication>
qguiapplicationNew(const QVector<QByteArray>& args)
{
  auto argsData = new ApplicationArgsData(args);
  auto ptr =
    ::std::unique_ptr<QGuiApplication>(new QApplication(argsData->size(), argsData->data()));
  Q_ASSERT(ptr != nullptr);
  argsData->setParent(ptr.get());

  return ptr;
}

} // namespace cxxqtlib1
} // namespace rust

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

int platformCursorGlobalX() {
    return QCursor::pos().x();
}

int platformCursorGlobalY() {
    return QCursor::pos().y();
}

// One icon for every window and the tray, bundled so it shows before the app
// is installed. Qt passes it to X11 window managers and, on Wayland, through
// xdg-toplevel-icon where the compositor supports it; other compositors look
// the icon up from the installed desktop entry named by the app id.
bool platformSetApplicationIcon() {
    QIcon icon;
    for (int size : {16, 22, 24, 32, 48, 64, 128, 256})
        icon.addFile(QStringLiteral(":/betternotes/icons/app-%1.png").arg(size),
                     QSize(size, size));
    if (icon.availableSizes().isEmpty())
        return false;
    QGuiApplication::setWindowIcon(icon);
    return true;
}

// The user's Pictures folder as a file URL, from the XDG user directories.
QString platformPicturesFolder() {
    return QUrl::fromLocalFile(
               QStandardPaths::writableLocation(QStandardPaths::PicturesLocation))
        .toString();
}
