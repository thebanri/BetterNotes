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
};
