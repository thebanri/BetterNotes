#include "image_animator.h"

#include <QAbstractTextDocumentLayout>
#include <QImage>
#include <QMovie>
#include <QSet>
#include <QTextBlock>
#include <QTextDocument>
#include <QTextFragment>
#include <QUrl>

namespace {
// Only local GIF files animate; a note's content must not make the app fetch
// anything from the network.
bool isLocalGif(const QString &name) {
    const QUrl url(name);
    return url.isLocalFile() &&
           url.path().endsWith(QStringLiteral(".gif"), Qt::CaseInsensitive);
}

// The keys a view may look an image up by. Qt 6.11 asks for the image's own
// URL. Qt 6.8 strips the file scheme and resolves the bare path against the
// document's base URL, which for a QML editor is its qrc: file, so a resource
// stored only under the file URL is never found there.
QList<QUrl> resourceKeys(const QTextDocument *document, const QString &name) {
    const QUrl url(name);
    QList<QUrl> keys{url};
    if (url.isLocalFile()) {
        const QUrl path(url.toLocalFile());
        for (const auto &key : {path, document->baseUrl().resolved(path)}) {
            if (!keys.contains(key))
                keys.append(key);
        }
    }
    return keys;
}

void addImage(QTextDocument *document, const QString &name,
              const QImage &image) {
    // Palette and 1-bit images (common for GIF frames and small PNGs) come out
    // black when the scene graph turns them into textures.
    const QImage converted =
        image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    for (const auto &key : resourceKeys(document, name))
        document->addResource(QTextDocument::ImageResource, key, converted);
}
} // namespace

ImageAnimator::~ImageAnimator() { clear(); }

void ImageAnimator::setDocument(QQuickTextDocument *document) {
    if (m_document == document)
        return;
    clear();
    m_document = document;
    emit documentChanged();
    refresh();
}

void ImageAnimator::setRunning(bool running) {
    if (m_running == running)
        return;
    m_running = running;
    for (auto *movie : std::as_const(m_movies)) {
        if (movie)
            movie->setPaused(!running);
    }
    emit runningChanged();
}

int ImageAnimator::animationCount() const {
    int count = 0;
    for (auto *movie : m_movies)
        count += movie ? 1 : 0;
    return count;
}

void ImageAnimator::refresh() {
    auto *document = m_document ? m_document->textDocument() : nullptr;
    if (!document) {
        clear();
        return;
    }
    QSet<QString> present;
    for (auto block = document->begin(); block.isValid(); block = block.next()) {
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto format = it.fragment().charFormat();
            if (!format.isImageFormat())
                continue;
            const QString name = format.toImageFormat().name();
            if (isLocalGif(name))
                present.insert(name);
            // Load each local image once under every key, so versions that
            // miss the file URL do not reread the file on every redraw.
            if (QUrl(name).isLocalFile() && !m_loaded.contains(name)) {
                m_loaded.insert(name);
                const QImage image(QUrl(name).toLocalFile());
                if (!image.isNull())
                    addImage(document, name, image);
            }
        }
    }
    bool changed = false;
    for (auto it = m_movies.begin(); it != m_movies.end();) {
        if (present.contains(it.key())) {
            ++it;
            continue;
        }
        delete it.value();
        it = m_movies.erase(it);
        changed = true;
    }
    for (const auto &name : std::as_const(present)) {
        if (m_movies.contains(name))
            continue;
        changed = true;
        auto *movie = new QMovie(QUrl(name).toLocalFile());
        // A still GIF, or one that cannot be read, stays as the document drew
        // it. Remember it anyway so it is not probed on every refresh.
        if (!movie->isValid() || movie->frameCount() == 1) {
            delete movie;
            m_movies.insert(name, nullptr);
            continue;
        }
        movie->setCacheMode(QMovie::CacheAll);
        connect(movie, &QMovie::frameChanged, this,
                [this, name] { showFrame(name); });
        m_movies.insert(name, movie);
        movie->start();
        movie->setPaused(!m_running);
    }
    if (changed)
        emit animationsChanged();
}

void ImageAnimator::showFrame(const QString &name) {
    auto *document = m_document ? m_document->textDocument() : nullptr;
    auto *movie = m_movies.value(name);
    if (!document || !movie)
        return;
    m_updating = true;
    emit updatingChanged();
    addImage(document, name, movie->currentImage());
    // Ask the view to redraw the blocks showing this image. The text and its
    // layout are unchanged, so this is not an edit and adds no undo step.
    auto *layout = document->documentLayout();
    for (auto block = document->begin(); block.isValid(); block = block.next()) {
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto format = it.fragment().charFormat();
            if (format.isImageFormat() &&
                format.toImageFormat().name() == name) {
                emit layout->updateBlock(block);
                break;
            }
        }
    }
    m_updating = false;
    emit updatingChanged();
}

void ImageAnimator::clear() {
    const bool had = !m_movies.isEmpty();
    m_loaded.clear();
    qDeleteAll(m_movies);
    m_movies.clear();
    if (had)
        emit animationsChanged();
}
