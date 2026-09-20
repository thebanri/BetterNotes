#include "platform_helper.h"
#include <QGuiApplication>
#include <QClipboard>
#include <QCursor>
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
