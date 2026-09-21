#pragma once

#include <QColor>
#include <QObject>
#include <QQuickTextDocument>
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
};
