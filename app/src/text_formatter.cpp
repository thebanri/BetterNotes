#include "text_formatter.h"

#include <QTextBlock>
#include <QTextCursor>
#include <QTextFragment>

namespace {
QTextCursor selection(QQuickTextDocument *quickDocument, int start, int end) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || start < 0 || end <= start ||
        end >= document->characterCount())
        return {};
    QTextCursor cursor(document);
    cursor.setPosition(start);
    cursor.setPosition(end, QTextCursor::KeepAnchor);
    return cursor;
}

bool hasStyle(const QTextCharFormat &format, const QString &style) {
    if (style == "b")
        return format.fontWeight() >= QFont::Bold;
    if (style == "i")
        return format.fontItalic();
    if (style == "u")
        return format.fontUnderline();
    return false;
}
} // namespace

bool TextFormatter::styleActive(QQuickTextDocument *document, int start,
                                int end, const QString &style) const {
    auto cursor = selection(document, start, end);
    if (cursor.isNull())
        return false;
    bool found = false;
    for (auto block = cursor.document()->findBlock(start);
         block.isValid() && block.position() < end; block = block.next()) {
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            if (!fragment.isValid() || fragment.position() >= end ||
                fragment.position() + fragment.length() <= start)
                continue;
            found = true;
            if (!hasStyle(fragment.charFormat(), style))
                return false;
        }
    }
    return found;
}

bool TextFormatter::sizeActive(QQuickTextDocument *document, int start, int end,
                               int pixelSize) const {
    auto cursor = selection(document, start, end);
    if (cursor.isNull())
        return false;
    bool found = false;
    for (auto block = cursor.document()->findBlock(start);
         block.isValid() && block.position() < end; block = block.next()) {
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            if (!fragment.isValid() || fragment.position() >= end ||
                fragment.position() + fragment.length() <= start)
                continue;
            found = true;
            if (fragment.charFormat().intProperty(QTextFormat::FontPixelSize) !=
                pixelSize)
                return false;
        }
    }
    return found;
}

void TextFormatter::toggleStyle(QQuickTextDocument *document, int start,
                                int end, const QString &style) {
    auto cursor = selection(document, start, end);
    if (cursor.isNull())
        return;
    const bool enabled = !styleActive(document, start, end, style);
    QTextCharFormat format;
    if (style == "b")
        format.setFontWeight(enabled ? QFont::Bold : QFont::Normal);
    else if (style == "i")
        format.setFontItalic(enabled);
    else if (style == "u")
        format.setFontUnderline(enabled);
    else
        return;
    cursor.mergeCharFormat(format);
}

void TextFormatter::heading(QQuickTextDocument *document, int start, int end,
                            int pixelSize, bool enabled) {
    auto cursor = selection(document, start, end);
    if (cursor.isNull() || pixelSize < 1 || pixelSize > 256)
        return;
    QTextCharFormat format;
    format.setProperty(QTextFormat::FontPixelSize, pixelSize);
    format.setFontWeight(enabled ? QFont::Bold : QFont::Normal);
    cursor.mergeCharFormat(format);
}

void TextFormatter::color(QQuickTextDocument *document, int start, int end,
                          const QColor &color, bool reset) {
    auto cursor = selection(document, start, end);
    if (cursor.isNull() || (!reset && !color.isValid()))
        return;
    if (!reset) {
        QTextCharFormat format;
        format.setForeground(color);
        cursor.mergeCharFormat(format);
        return;
    }
    // Clearing a property via merge cannot remove it. Preserve every fragment's
    // other properties and group the changes into one undo operation.
    cursor.beginEditBlock();
    for (auto block = cursor.document()->findBlock(start);
         block.isValid() && block.position() < end; block = block.next()) {
        // Collect before editing: changing formats invalidates fragment
        // iterators.
        struct Run {
            int start;
            int end;
            QTextCharFormat format;
        };
        QList<Run> runs;
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            if (!fragment.isValid() || fragment.position() >= end ||
                fragment.position() + fragment.length() <= start)
                continue;
            auto format = fragment.charFormat();
            format.clearProperty(QTextFormat::ForegroundBrush);
            runs.append({qMax(start, fragment.position()),
                         qMin(end, fragment.position() + fragment.length()),
                         format});
        }
        for (const auto &run : runs) {
            QTextCursor part(cursor.document());
            part.setPosition(run.start);
            part.setPosition(run.end, QTextCursor::KeepAnchor);
            part.setCharFormat(run.format);
        }
    }
    cursor.endEditBlock();
}
