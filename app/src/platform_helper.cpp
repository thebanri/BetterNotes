#include "platform_helper.h"
#include <QGuiApplication>
#include <QClipboard>
#include <QCursor>
#include <QDateTime>
#include <QDir>
#include <QIcon>
#include <QImage>
#include <QMimeData>
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

// The user's Documents folder as a file URL, where exports are offered.
QString platformDocumentsFolder() {
    return QUrl::fromLocalFile(
               QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation))
        .toString();
}

// An image on the clipboard (a screenshot, or one copied from a browser)
// written to a new PNG in the temporary folder; its path, or "" when the
// clipboard holds no image data. The caller removes the file.
QString platformClipboardImageToFile() {
    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    const QMimeData *data = app && app->clipboard() ? app->clipboard()->mimeData() : nullptr;
    if (!data || !data->hasImage())
        return {};
    // Office apps put a picture of copied text beside the text itself; that
    // is a text paste. Browsers copying an image add just its address.
    const QString text = data->text().trimmed();
    if (!text.isEmpty() && (text.contains(u'\n') || text.contains(u' ')))
        return {};
    const QImage image = qvariant_cast<QImage>(data->imageData());
    if (image.isNull())
        return {};
    const QString path =
        QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation))
            .filePath(QStringLiteral("betternotes-pasted-%1.png")
                          .arg(QDateTime::currentMSecsSinceEpoch()));
    return image.save(path, "PNG") ? path : QString();
}

// Files copied in a file manager, as newline-separated file URLs.
QString platformClipboardImageUrls() {
    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    const QMimeData *data = app && app->clipboard() ? app->clipboard()->mimeData() : nullptr;
    if (!data || !data->hasUrls())
        return {};
    QStringList urls;
    for (const auto &url : data->urls()) {
        if (url.isLocalFile())
            urls.append(url.toString());
    }
    return urls.join(u'\n');
}
