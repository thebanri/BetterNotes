#include "text_formatter.h"

#include <QImage>
#include <QImageReader>
#include <QPixmap>
#include <QRegularExpression>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextFragment>
#include <QTextList>

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

namespace {
// A code block's background: grey, part transparent, so it reads on light
// and dark notes alike. HTML keeps it as rgba(), which is how a code block is
// recognised when a note is opened again.
const QColor codeBackground(128, 128, 128, 46);

bool isCodeBlock(const QTextBlock &block) {
    const auto brush = block.blockFormat().background();
    if (brush.style() == Qt::NoBrush)
        return false;
    const auto color = brush.color();
    return color.red() == codeBackground.red() &&
           color.green() == codeBackground.green() &&
           color.blue() == codeBackground.blue() && color.alpha() > 0 &&
           color.alpha() < 255;
}

QTextCharFormat codeFont() {
    QTextCharFormat format;
    format.setFontFamilies(QStringList{QStringLiteral("monospace")});
    format.setFontFixedPitch(true);
    return format;
}

// Makes one paragraph code, or plain text again, keeping its other formats.
void setCode(const QTextBlock &block, bool code) {
    QTextCursor cursor(block);
    auto blockFormat = cursor.blockFormat();
    // The margin keeps code clear of the edge of the box drawn behind it.
    if (code) {
        blockFormat.setBackground(codeBackground);
        blockFormat.setLeftMargin(8);
        blockFormat.setRightMargin(8);
    } else {
        blockFormat.clearBackground();
        blockFormat.setLeftMargin(0);
        blockFormat.setRightMargin(0);
    }
    cursor.setBlockFormat(blockFormat);

    // Collect before editing: changing formats invalidates fragment iterators.
    QList<QPair<QPair<int, int>, QTextCharFormat>> runs;
    for (auto it = block.begin(); !it.atEnd(); ++it) {
        const auto fragment = it.fragment();
        auto format = fragment.charFormat();
        if (format.isImageFormat())
            continue;
        if (code) {
            format.merge(codeFont());
        } else {
            format.clearProperty(QTextFormat::FontFamilies);
            format.clearProperty(QTextFormat::FontFixedPitch);
        }
        runs.append({{fragment.position(), fragment.position() + fragment.length()},
                     format});
    }
    for (const auto &run : runs) {
        QTextCursor part(cursor.document());
        part.setPosition(run.first.first);
        part.setPosition(run.first.second, QTextCursor::KeepAnchor);
        part.setCharFormat(run.second);
    }
    auto charFormat = block.charFormat();
    if (code) {
        charFormat.merge(codeFont());
    } else {
        charFormat.clearProperty(QTextFormat::FontFamilies);
        charFormat.clearProperty(QTextFormat::FontFixedPitch);
    }
    cursor.setBlockCharFormat(charFormat);
    // Typing continues in the paragraph's own format.
    cursor.setCharFormat(charFormat);
}

// "- ", "* ", "• " and ". " start a bulleted list; "1. " or "1) " starts a
// numbered list at that number. Anything else is ordinary text.
bool listStyleFor(const QString &prefix, QTextListFormat::Style *style,
                  int *start) {
    static const QRegularExpression numbered(
        QStringLiteral(R"(^(\d{1,3})[.)] $)"));
    if (prefix == QStringLiteral("- ") || prefix == QStringLiteral("* ") ||
        prefix == QStringLiteral("\u2022 ") || prefix == QStringLiteral(". ")) {
        *style = QTextListFormat::ListDisc;
        *start = 1;
        return true;
    }
    const auto match = numbered.match(prefix);
    if (!match.hasMatch())
        return false;
    *style = QTextListFormat::ListDecimal;
    *start = qMax(1, match.captured(1).toInt());
    return true;
}

// The image character at a document position, if there is one.
QTextImageFormat imageFormatAt(QTextDocument *document, int position) {
    if (!document || position < 0 || position >= document->characterCount() - 1)
        return {};
    const auto block = document->findBlock(position);
    for (auto it = block.begin(); !it.atEnd(); ++it) {
        const auto fragment = it.fragment();
        if (position >= fragment.position() &&
            position < fragment.position() + fragment.length()) {
            const auto format = fragment.charFormat();
            return format.isImageFormat() ? format.toImageFormat()
                                          : QTextImageFormat();
        }
    }
    return {};
}

// The image's own size, from the document's loaded resource when it has one.
QSize naturalImageSize(QTextDocument *document, const QString &name) {
    const QVariant resource =
        document->resource(QTextDocument::ImageResource, QUrl(name));
    if (resource.canConvert<QImage>()) {
        const auto image = resource.value<QImage>();
        if (!image.isNull())
            return image.size();
    }
    if (resource.canConvert<QPixmap>()) {
        const auto pixmap = resource.value<QPixmap>();
        if (!pixmap.isNull())
            return pixmap.size();
    }
    const QUrl url(name);
    return QImageReader(url.isLocalFile() ? url.toLocalFile() : name).size();
}
} // namespace

bool TextFormatter::startsList(const QString &text, int position) const {
    if (position < 0 || position > text.size())
        return false;
    const int lineStart = int(text.lastIndexOf(u'\n', position - 1)) + 1;
    QTextListFormat::Style style;
    int start;
    return listStyleFor(text.mid(lineStart, position - lineStart), &style,
                        &start);
}

int TextFormatter::autoList(QQuickTextDocument *quickDocument, int position) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount())
        return -1;
    const auto block = document->findBlock(position);
    if (!block.isValid() || block.textList() || isCodeBlock(block))
        return -1;
    QTextListFormat::Style style;
    int start;
    if (!listStyleFor(block.text().left(position - block.position()), &style,
                      &start))
        return -1;
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    cursor.setPosition(block.position());
    cursor.setPosition(position, QTextCursor::KeepAnchor);
    cursor.removeSelectedText();
    QTextListFormat format;
    format.setStyle(style);
    format.setStart(start);
    format.setIndent(1);
    cursor.createList(format);
    cursor.endEditBlock();
    return block.position();
}

bool TextFormatter::endEmptyListItem(QQuickTextDocument *quickDocument,
                                     int position) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount())
        return false;
    const auto block = document->findBlock(position);
    auto *list = block.textList();
    if (!list || !block.text().isEmpty())
        return false;
    QTextCursor cursor(block);
    cursor.beginEditBlock();
    list->remove(block);
    auto format = cursor.blockFormat();
    format.setIndent(0);
    cursor.setBlockFormat(format);
    cursor.endEditBlock();
    return true;
}

QVariantMap TextFormatter::imageAt(QQuickTextDocument *quickDocument,
                                   int position) const {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    const auto format = imageFormatAt(document, position);
    if (!format.isValid() || format.name().isEmpty())
        return {};
    const QSize natural = naturalImageSize(document, format.name());
    qreal width = format.hasProperty(QTextFormat::ImageWidth)
                      ? format.width()
                      : natural.width();
    qreal height = format.hasProperty(QTextFormat::ImageHeight)
                       ? format.height()
                       : (natural.width() > 0
                              ? width * natural.height() / natural.width()
                              : natural.height());
    return {{QStringLiteral("name"), format.name()},
            {QStringLiteral("width"), qRound(width)},
            {QStringLiteral("height"), qRound(height)}};
}

bool TextFormatter::resizeImage(QQuickTextDocument *quickDocument, int position,
                                int width) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    auto format = imageFormatAt(document, position);
    if (!format.isValid() || width < 1)
        return false;
    format.setWidth(qBound(24, width, 4096));
    // Without a height Qt keeps the image's aspect ratio.
    format.clearProperty(QTextFormat::ImageHeight);
    QTextCursor cursor(document);
    cursor.setPosition(position);
    cursor.setPosition(position + 1, QTextCursor::KeepAnchor);
    cursor.setCharFormat(format);
    return true;
}

int TextFormatter::fittedImageWidth(const QUrl &url, int maxWidth) const {
    if (!url.isLocalFile())
        return 0;
    const QSize size = QImageReader(url.toLocalFile()).size();
    if (!size.isValid() || size.isEmpty())
        return 0;
    return qMax(16, qMin(size.width(), qMax(16, maxWidth)));
}

namespace {
bool isBullet(QTextListFormat::Style style) {
    return style == QTextListFormat::ListDisc ||
           style == QTextListFormat::ListCircle ||
           style == QTextListFormat::ListSquare;
}

bool matchesKind(const QTextList *list, const QString &kind) {
    return list && isBullet(list->format().style()) == (kind == u"bullet");
}

// The paragraphs a selection touches; an empty selection is its paragraph.
QList<QTextBlock> blocksIn(QTextDocument *document, int start, int end) {
    QList<QTextBlock> blocks;
    if (!document || start < 0 || end < start ||
        end >= document->characterCount())
        return blocks;
    for (auto block = document->findBlock(start); block.isValid();
         block = block.next()) {
        blocks.append(block);
        if (block.position() + block.length() > end)
            break;
    }
    return blocks;
}
} // namespace

bool TextFormatter::listActive(QQuickTextDocument *quickDocument, int start,
                               int end, const QString &kind) const {
    const auto blocks = blocksIn(
        quickDocument ? quickDocument->textDocument() : nullptr, start, end);
    if (blocks.isEmpty())
        return false;
    for (const auto &block : blocks) {
        if (!matchesKind(block.textList(), kind))
            return false;
    }
    return true;
}

void TextFormatter::toggleList(QQuickTextDocument *quickDocument, int start,
                               int end, const QString &kind) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    const auto blocks = blocksIn(document, start, end);
    if (blocks.isEmpty() || (kind != u"bullet" && kind != u"number"))
        return;
    const bool remove = listActive(quickDocument, start, end, kind);
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    // Take every paragraph out of whatever list it is in first, so a mixed
    // selection becomes one list rather than several.
    for (const auto &block : blocks) {
        if (auto *list = block.textList())
            list->remove(block);
        QTextCursor paragraph(block);
        auto format = paragraph.blockFormat();
        format.setIndent(0);
        paragraph.setBlockFormat(format);
    }
    if (!remove) {
        QTextListFormat format;
        format.setStyle(kind == u"bullet" ? QTextListFormat::ListDisc
                                          : QTextListFormat::ListDecimal);
        format.setIndent(1);
        QTextCursor first(blocks.first());
        auto *list = first.createList(format);
        for (qsizetype i = 1; i < blocks.size(); ++i)
            list->add(blocks.at(i));
    }
    cursor.endEditBlock();
}

int TextFormatter::codeFence(QQuickTextDocument *quickDocument, int position) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount())
        return -1;
    static const QRegularExpression fence(QStringLiteral(R"(^\s*```[\w+#.-]*\s*$)"));
    const auto block = document->findBlock(position);
    if (!block.isValid() || block.textList() || !fence.match(block.text()).hasMatch())
        return -1;
    const bool inside = isCodeBlock(block);
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    cursor.setPosition(block.position());
    cursor.setPosition(block.position() + block.length() - 1,
                       QTextCursor::KeepAnchor);
    cursor.removeSelectedText();
    // The block handle stays valid; the old position may now be past it.
    setCode(block, !inside);
    cursor.endEditBlock();
    return block.position();
}

bool TextFormatter::codeActive(QQuickTextDocument *quickDocument, int start,
                               int end) const {
    const auto blocks = blocksIn(
        quickDocument ? quickDocument->textDocument() : nullptr, start, end);
    if (blocks.isEmpty())
        return false;
    for (const auto &block : blocks) {
        if (!isCodeBlock(block))
            return false;
    }
    return true;
}

void TextFormatter::toggleCode(QQuickTextDocument *quickDocument, int start,
                               int end) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    const auto blocks = blocksIn(document, start, end);
    if (blocks.isEmpty())
        return;
    const bool code = !codeActive(quickDocument, start, end);
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    for (const auto &block : blocks) {
        // Code is not a list item; take it out of any list first.
        if (code) {
            if (auto *list = block.textList()) {
                list->remove(block);
                QTextCursor paragraph(block);
                auto format = paragraph.blockFormat();
                format.setIndent(0);
                paragraph.setBlockFormat(format);
            }
        }
        setCode(block, code);
    }
    cursor.endEditBlock();
}

void TextFormatter::restoreCodeFont(QQuickTextDocument *quickDocument) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document)
        return;
    bool changed = false;
    for (auto block = document->begin(); block.isValid(); block = block.next()) {
        if (!isCodeBlock(block) || !block.text().isEmpty() ||
            block.charFormat().fontFixedPitch())
            continue;
        QTextCursor cursor(block);
        auto format = block.charFormat();
        format.merge(codeFont());
        cursor.setBlockCharFormat(format);
        changed = true;
    }
    // Called right after a note loads, when there is nothing to undo yet;
    // this repair must not become the first undo step.
    if (changed)
        document->clearUndoRedoStacks();
}

QVariantList TextFormatter::codeBlocks(QQuickTextDocument *quickDocument) const {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    QVariantList runs;
    if (!document)
        return runs;
    int start = -1;
    int end = -1;
    for (auto block = document->begin(); block.isValid(); block = block.next()) {
        if (isCodeBlock(block)) {
            if (start < 0)
                start = block.position();
            end = block.position() + block.length() - 1;
            continue;
        }
        if (start >= 0)
            runs.append(QVariantMap{{QStringLiteral("start"), start},
                                    {QStringLiteral("end"), end}});
        start = -1;
    }
    if (start >= 0)
        runs.append(QVariantMap{{QStringLiteral("start"), start},
                                {QStringLiteral("end"), end}});
    return runs;
}
