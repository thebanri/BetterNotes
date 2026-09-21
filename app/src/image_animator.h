#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QQuickTextDocument>
#include <QtQml/qqmlregistration.h>

class QMovie;

// Plays the animated GIFs shown in a text document. QTextDocument draws an
// image resource as a single still frame, so each GIF's frames are fed back
// into the document as that image resource while the animation runs. It also
// registers the document's other local images, which Qt 6.8 would otherwise
// fail to find by their file URL (see resourceKeys()).
class ImageAnimator : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QQuickTextDocument *document READ document WRITE setDocument
                   NOTIFY documentChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    // True while a frame is being swapped in. The document reports that as a
    // content change, which is not an edit and must not be saved.
    Q_PROPERTY(bool updating READ updating NOTIFY updatingChanged)
    Q_PROPERTY(int animationCount READ animationCount NOTIFY animationsChanged)
  public:
    explicit ImageAnimator(QObject *parent = nullptr) : QObject(parent) {}
    ~ImageAnimator() override;

    QQuickTextDocument *document() const { return m_document; }
    void setDocument(QQuickTextDocument *document);
    bool running() const { return m_running; }
    void setRunning(bool running);
    bool updating() const { return m_updating; }
    int animationCount() const;

    // Finds the document's GIFs, starting new ones and dropping removed ones.
    Q_INVOKABLE void refresh();

  signals:
    void documentChanged();
    void runningChanged();
    void updatingChanged();
    void animationsChanged();

  private:
    void showFrame(const QString &name);
    void clear();

    QPointer<QQuickTextDocument> m_document;
    QHash<QString, QMovie *> m_movies;
    QSet<QString> m_loaded;
    bool m_running = true;
    bool m_updating = false;
};
