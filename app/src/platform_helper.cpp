#include "platform_helper.h"
#include <QGuiApplication>
#include <QClipboard>
#include <QCursor>
#include <QDateTime>
#include <QDir>
#include <QIcon>
#include <QImage>
#include <QFile>
#include <QMimeData>
#include <QMimeDatabase>
#include <QRegularExpression>
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

// Hands another process's xdg-activation token to the next window that is
// shown or activated. On Wayland only a request carrying a token from the
// compositor may move focus to a window. Qt's xdg-shell integration and
// LayerShellQt both take the token from XDG_ACTIVATION_TOKEN and clear it
// once used; X11 has no such tokens.
void platformSetActivationToken(const QString& token) {
    if (QGuiApplication::platformName() == QLatin1String("wayland"))
        qputenv("XDG_ACTIVATION_TOKEN", token.toUtf8());
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

// Marks clipboard contents already given their images.
static const QString copiedImagesFormat = QStringLiteral("application/x-betternotes-images");

// Note text copied with images in it names each image by its file in the
// note's attachments. Other apps cannot use that: plain text holds U+FFFC in
// its place and a browser will not load a local file. Once such a copy lands
// on the clipboard it is replaced with one where the HTML carries the images
// themselves and the plain text leaves them out. A single image is also
// offered as a picture, so apps that take only text or only a picture can
// paste either one. Qt's own rich text format keeps the file names, so
// pasting into a note still refers to its attachments.
static void giveCopiedImages(QClipboard *clipboard) {
    // Another app's copy is left alone. The offscreen clipboard (tests) never
    // reports an owner, but it only ever holds this app's data.
    if (!clipboard->ownsClipboard() && QGuiApplication::platformName() != QLatin1String("offscreen"))
        return;
    const QMimeData *source = clipboard->mimeData();
    if (!source || source->hasFormat(copiedImagesFormat) || !source->hasHtml())
        return;
    const QString html = source->html();
    static const QRegularExpression imageSource(QStringLiteral(R"re(<img\s[^>]*?src="(file://[^"]*)")re"));
    // An image larger than this stays a file name rather than filling the clipboard.
    constexpr qint64 maximumBytes = 20 * 1024 * 1024;
    QString embedded;
    QStringList paths;
    qsizetype done = 0;
    for (const auto &match : imageSource.globalMatch(html)) {
        const QString path = QUrl(match.captured(1).replace(QStringLiteral("&amp;"), QStringLiteral("&"))).toLocalFile();
        QFile file(path);
        if (path.isEmpty() || file.size() > maximumBytes || !file.open(QIODevice::ReadOnly))
            continue;
        paths.append(path);
        embedded += html.mid(done, match.capturedStart(1) - done);
        embedded += QStringLiteral("data:%1;base64,").arg(QMimeDatabase().mimeTypeForFile(path).name());
        embedded += QString::fromLatin1(file.readAll().toBase64());
        done = match.capturedEnd(1);
    }
    if (done == 0)
        return;
    embedded += html.mid(done);
    static const QRegularExpression imageLine(QStringLiteral(R"re((?m)^\x{FFFC}+\n)re"));
    const QString text = source->text().remove(imageLine).remove(QChar::ObjectReplacementCharacter);
    // A single image selected on its own is copied as Copy Image does: file
    // managers then paste the file instead of saving Qt's document format.
    if (text.trimmed().isEmpty() && paths.size() == 1 && platformCopyImageFile(paths.first()))
        return;

    auto *data = new QMimeData;
    // Every plain text variant is replaced: text() prefers the UTF-8 one.
    for (const QString &format : source->formats()) {
        if (!format.startsWith(QLatin1String("text/plain")) && format != QLatin1String("text/html"))
            data->setData(format, source->data(format));
    }
    data->setData(QStringLiteral("application/x-qrichtext"), html.toUtf8());
    data->setHtml(embedded);
    // With only images selected there is no text to offer; an empty line
    // would be pasted instead of the picture.
    if (!text.trimmed().isEmpty())
        data->setText(text);
    if (paths.size() == 1) {
        const QImage image(paths.first());
        if (!image.isNull())
            data->setImageData(image);
    }
    data->setData(copiedImagesFormat, {});
    clipboard->setMimeData(data);
}

void platformKeepCopiedImages() {
    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    if (!app || !app->clipboard())
        return;
    QClipboard *clipboard = app->clipboard();
    QObject::connect(clipboard, &QClipboard::dataChanged, clipboard,
                     [clipboard] { giveCopiedImages(clipboard); });
}

// An image on the clipboard (a screenshot, or one copied from a browser)
// written to a new PNG in the temporary folder; its path, or "" when the
// clipboard holds no image data. The caller removes the file.
QString platformClipboardImageToFile() {
    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    const QMimeData *data = app && app->clipboard() ? app->clipboard()->mimeData() : nullptr;
    // Text copied from a note with its image is pasted as that text.
    if (!data || !data->hasImage() || data->hasFormat(copiedImagesFormat))
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

// Puts an image file on the clipboard as a picture, so other apps can paste
// it, together with its file URL for file managers.
bool platformCopyImageFile(const QString& path) {
    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    if (!app || !app->clipboard())
        return false;
    const QImage image(path);
    if (image.isNull())
        return false;
    auto *data = new QMimeData;
    data->setImageData(image);
    data->setUrls({QUrl::fromLocalFile(path)});
    app->clipboard()->setMimeData(data);
    return true;
}
