#include "image_animator.h"

#include <QAbstractTextDocumentLayout>
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
            if (format.isImageFormat()) {
                const QString name = format.toImageFormat().name();
                if (isLocalGif(name))
                    present.insert(name);
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
    document->addResource(QTextDocument::ImageResource, QUrl(name),
                          movie->currentImage());
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
    qDeleteAll(m_movies);
    m_movies.clear();
    if (had)
        emit animationsChanged();
}
