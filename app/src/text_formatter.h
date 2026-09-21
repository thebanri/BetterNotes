#pragma once

#include <QColor>
#include <QObject>
#include <QQuickTextDocument>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Presentation-only adapter: merge individual Qt text properties without
// replacing the document, mixed formatting, selection, or its undo stack.
class TextFormatter : public QObject {
    Q_OBJECT
    QML_ELEMENT
  public:
    explicit TextFormatter(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE bool styleActive(QQuickTextDocument *document, int start,
                                 int end, const QString &style) const;
    Q_INVOKABLE bool sizeActive(QQuickTextDocument *document, int start,
                                int end, int pixelSize) const;
    Q_INVOKABLE void toggleStyle(QQuickTextDocument *document, int start,
                                 int end, const QString &style);
    Q_INVOKABLE void heading(QQuickTextDocument *document, int start, int end,
                             int pixelSize, bool enabled);
    Q_INVOKABLE void color(QQuickTextDocument *document, int start, int end,
                           const QColor &color, bool reset);
    // Turns every web address in the document into an underlined link and
    // stops a link's formatting from spreading into text typed after it.
    // Returns how many ranges changed, so the caller only saves real changes.
    Q_INVOKABLE int linkify(QQuickTextDocument *document, const QColor &color);
    // Whether plain text contains something linkify would turn into a link.
    Q_INVOKABLE bool containsLink(const QString &text) const;
    // The link target of the character at a document position, or empty.
    Q_INVOKABLE QString anchorAt(QQuickTextDocument *document, int position) const;

    // Turns a paragraph that starts with a list marker ("- ", "* ", ". " or
    // "1. ") into a bulleted or numbered list item once the marker is typed.
    // Returns the caret position after the marker is removed, or -1.
    Q_INVOKABLE int autoList(QQuickTextDocument *document, int position);
    // Whether plain text has a list marker at the start of the line ending at
    // position, so the caller knows to switch the note to rich text first.
    Q_INVOKABLE bool startsList(const QString &text, int position) const;
    // Whether every paragraph from start to end is in a list of this kind,
    // "bullet" or "number".
    Q_INVOKABLE bool listActive(QQuickTextDocument *document, int start, int end,
                                const QString &kind) const;
    // Makes the paragraphs from start to end one list of this kind, or takes
    // them out of it when they already are one.
    Q_INVOKABLE void toggleList(QQuickTextDocument *document, int start, int end,
                                const QString &kind);
    // Enter on an empty list item ends the list instead of adding an item.
    Q_INVOKABLE bool endEmptyListItem(QQuickTextDocument *document, int position);

    // The image at a document position: {name, width, height}, or an empty
    // map. Width and height are the displayed size in pixels.
    Q_INVOKABLE QVariantMap imageAt(QQuickTextDocument *document,
                                    int position) const;
    // Displays the image at position with the given width; the height follows
    // the image's aspect ratio.
    Q_INVOKABLE bool resizeImage(QQuickTextDocument *document, int position,
                                 int width);
    // The displayed width for a newly inserted image: its natural width, but
    // never wider than maxWidth. Returns 0 when the file is not an image.
    Q_INVOKABLE int fittedImageWidth(const QUrl &url, int maxWidth) const;
};
