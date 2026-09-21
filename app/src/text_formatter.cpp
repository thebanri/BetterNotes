#include "text_formatter.h"

#include <QRegularExpression>
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

namespace {
// Addresses start with a web scheme or "www." and run to the next space or
// character that cannot appear unquoted in a URL.
const QRegularExpression &linkPattern() {
    static const QRegularExpression pattern(
        QStringLiteral(R"((?:https?://|www\.)[^\s<>"'`]+)"),
        QRegularExpression::CaseInsensitiveOption);
    return pattern;
}

// Sentence punctuation right after an address belongs to the sentence:
// "see https://example.com." links "https://example.com".
qsizetype trimmedLength(const QString &match) {
    qsizetype length = match.size();
    while (length > 0) {
        const QChar last = match.at(length - 1);
        if (QStringLiteral(".,;:!?'\"").contains(last)) {
            --length;
        } else if (last == u')' &&
                   match.left(length).count(u'(') <
                       match.left(length).count(u')')) {
            --length; // "(https://example.com)" keeps its own parenthesis.
        } else {
            break;
        }
    }
    return length;
}

struct Run {
    int start;
    int end;
    QTextCharFormat format;
};
} // namespace

bool TextFormatter::containsLink(const QString &text) const {
    return linkPattern().match(text).hasMatch();
}

QString TextFormatter::anchorAt(QQuickTextDocument *quickDocument,
                                int position) const {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount() - 1)
        return {};
    const auto block = document->findBlock(position);
    for (auto it = block.begin(); !it.atEnd(); ++it) {
        const auto fragment = it.fragment();
        if (position >= fragment.position() &&
            position < fragment.position() + fragment.length()) {
            const auto format = fragment.charFormat();
            return format.isAnchor() ? format.anchorHref() : QString();
        }
    }
    return {};
}

int TextFormatter::linkify(QQuickTextDocument *quickDocument,
                           const QColor &color) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document)
        return 0;
    QList<Run> runs;
    for (auto block = document->begin(); block.isValid(); block = block.next()) {
        const QString text = block.text();
        auto matches = linkPattern().globalMatch(text);
        while (matches.hasNext()) {
            const auto match = matches.next();
            const qsizetype length = trimmedLength(match.captured());
            if (length == 0)
                continue;
            const int start = block.position() + int(match.capturedStart());
            const int end = start + int(length);
            QString href = match.captured().left(length);
            if (href.startsWith(QStringLiteral("www."), Qt::CaseInsensitive))
                href.prepend(QStringLiteral("https://"));

            // Collect before editing: changing formats invalidates fragment
            // iterators.
            bool linked = true;
            for (auto it = block.begin(); !it.atEnd(); ++it) {
                const auto fragment = it.fragment();
                const int fragmentStart = fragment.position();
                const int fragmentEnd = fragmentStart + fragment.length();
                const auto format = fragment.charFormat();
                if (fragmentEnd > start && fragmentStart < end &&
                    (!format.isAnchor() || format.anchorHref() != href))
                    linked = false;
                // Text typed right after a link inherits its format. Anything
                // that carries this link's href beyond the address is spill.
                if (fragmentEnd > end && format.isAnchor() &&
                    format.anchorHref() == href && fragmentStart <= end + 1) {
                    auto plain = format;
                    plain.setAnchor(false);
                    plain.clearProperty(QTextFormat::AnchorHref);
                    plain.setFontUnderline(false);
                    plain.clearForeground();
                    runs.append({qMax(end, fragmentStart), fragmentEnd, plain});
                }
            }
            if (!linked) {
                QTextCharFormat format;
                format.setAnchor(true);
                format.setAnchorHref(href);
                format.setFontUnderline(true);
                if (color.isValid())
                    format.setForeground(color);
                // Marks a merge rather than a replacement, below.
                format.setProperty(QTextFormat::UserProperty, true);
                runs.append({start, end, format});
            }
        }
    }
    if (runs.isEmpty())
        return 0;
    QTextCursor cursor(document);
    // Fold into the edit that produced the address, so one undo removes both.
    cursor.joinPreviousEditBlock();
    for (auto run : runs) {
        QTextCursor part(document);
        part.setPosition(run.start);
        part.setPosition(run.end, QTextCursor::KeepAnchor);
        if (run.format.hasProperty(QTextFormat::UserProperty)) {
            run.format.clearProperty(QTextFormat::UserProperty);
            part.mergeCharFormat(run.format);
        } else {
            part.setCharFormat(run.format);
        }
    }
    cursor.endEditBlock();
    return int(runs.size());
}
