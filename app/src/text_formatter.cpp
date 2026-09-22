#include "text_formatter.h"

#include <QImage>
#include <algorithm>
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
            // Code is not a ticked checklist item.
            format.setFontStrikeOut(false);
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
        charFormat.setFontStrikeOut(false);
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
                  int *start,
                  QTextBlockFormat::MarkerType *marker = nullptr) {
    static const QRegularExpression numbered(
        QStringLiteral(R"(^(\d{1,3})[.)] $)"));
    static const QRegularExpression checkbox(QStringLiteral(R"(^\[( |x|X)?\] $)"));
    if (marker)
        *marker = QTextBlockFormat::MarkerType::NoMarker;
    if (const auto box = checkbox.match(prefix); box.hasMatch()) {
        *style = QTextListFormat::ListDisc;
        *start = 1;
        if (marker)
            *marker = box.captured(1).trimmed().isEmpty()
                          ? QTextBlockFormat::MarkerType::Unchecked
                          : QTextBlockFormat::MarkerType::Checked;
        return true;
    }
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
    QTextBlockFormat::MarkerType marker;
    if (!listStyleFor(block.text().left(position - block.position()), &style,
                      &start, &marker))
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
    if (marker != QTextBlockFormat::MarkerType::NoMarker) {
        auto blockFormat = cursor.blockFormat();
        blockFormat.setMarker(marker);
        cursor.setBlockFormat(blockFormat);
    }
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
    format.setMarker(QTextBlockFormat::MarkerType::NoMarker);
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

bool isChecklistItem(const QTextBlock &block) {
    return block.textList() && block.blockFormat().marker() !=
                                   QTextBlockFormat::MarkerType::NoMarker;
}

// "bullet", "number" or "check": a checklist is a bulleted list whose items
// carry a checkbox marker.
bool matchesKind(const QTextBlock &block, const QString &kind) {
    const auto *list = block.textList();
    if (!list)
        return false;
    if (kind == u"check")
        return isChecklistItem(block);
    return !isChecklistItem(block) &&
           isBullet(list->format().style()) == (kind == u"bullet");
}

void setMarker(const QTextBlock &block, QTextBlockFormat::MarkerType marker) {
    QTextCursor cursor(block);
    auto format = cursor.blockFormat();
    format.setMarker(marker);
    cursor.setBlockFormat(format);
}

// A ticked checklist item's text is struck through; images are left alone.
void setStruckOut(const QTextBlock &block, bool struck) {
    QList<QPair<QPair<int, int>, QTextCharFormat>> runs;
    for (auto it = block.begin(); !it.atEnd(); ++it) {
        const auto fragment = it.fragment();
        auto format = fragment.charFormat();
        if (format.isImageFormat())
            continue;
        format.setFontStrikeOut(struck);
        runs.append({{fragment.position(), fragment.position() + fragment.length()}, format});
    }
    QTextCursor cursor(block);
    for (const auto &run : runs) {
        QTextCursor part(cursor.document());
        part.setPosition(run.first.first);
        part.setPosition(run.first.second, QTextCursor::KeepAnchor);
        part.setCharFormat(run.second);
    }
    auto blockCharFormat = block.charFormat();
    blockCharFormat.setFontStrikeOut(struck);
    cursor.setBlockCharFormat(blockCharFormat);
}

// The paragraphs a selection touches; an empty selection is its paragraph.
QList<QTextBlock> blocksIn(QTextDocument *document, int start, int end) {
    QList<QTextBlock> blocks;
    if (!document || start < 0 || end < start ||
        end >= document->characterCount())
        return blocks;
    auto first = document->findBlock(start);
    auto last = document->findBlock(end);
    // A selection starting after the last character of a paragraph, or
    // ending before the first one of the next, only touches the line break
    // between them: dragging from the end of a line takes in no text of it.
    if (end > start) {
        if (first != last && first.length() > 1 &&
            start == first.position() + first.length() - 1)
            first = first.next();
        if (first != last && end == last.position())
            last = last.previous();
    }
    for (auto block = first; block.isValid(); block = block.next()) {
        blocks.append(block);
        if (block == last)
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
        if (!matchesKind(block, kind))
            return false;
    }
    return true;
}

void TextFormatter::toggleList(QQuickTextDocument *quickDocument, int start,
                               int end, const QString &kind) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    const auto blocks = blocksIn(document, start, end);
    if (blocks.isEmpty() ||
        (kind != u"bullet" && kind != u"number" && kind != u"check"))
        return;
    const bool remove = listActive(quickDocument, start, end, kind);
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    // Take every paragraph out of whatever list it is in first, so a mixed
    // selection becomes one list rather than several.
    for (const auto &block : blocks) {
        const bool ticked =
            block.blockFormat().marker() == QTextBlockFormat::MarkerType::Checked;
        if (auto *list = block.textList())
            list->remove(block);
        QTextCursor paragraph(block);
        auto format = paragraph.blockFormat();
        format.setIndent(0);
        format.setMarker(QTextBlockFormat::MarkerType::NoMarker);
        paragraph.setBlockFormat(format);
        if (ticked)
            setStruckOut(block, false);
    }
    if (!remove) {
        QTextListFormat format;
        format.setStyle(kind == u"number" ? QTextListFormat::ListDecimal
                                          : QTextListFormat::ListDisc);
        format.setIndent(1);
        QTextCursor first(blocks.first());
        auto *list = first.createList(format);
        for (qsizetype i = 1; i < blocks.size(); ++i)
            list->add(blocks.at(i));
        if (kind == u"check") {
            for (const auto &block : blocks)
                setMarker(block, QTextBlockFormat::MarkerType::Unchecked);
        }
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

namespace {
// A paragraph holding only images. Code formatting never applies to one, so
// a selection that runs over an image leaves the image as it is.
bool isImageOnly(const QTextBlock &block) {
    const QString text = block.text();
    return !text.isEmpty() &&
           std::all_of(text.cbegin(), text.cend(), [](QChar c) {
               return c == QChar::ObjectReplacementCharacter;
           });
}
} // namespace

bool TextFormatter::codeActive(QQuickTextDocument *quickDocument, int start,
                               int end) const {
    const auto blocks = blocksIn(
        quickDocument ? quickDocument->textDocument() : nullptr, start, end);
    bool any = false;
    for (const auto &block : blocks) {
        if (isImageOnly(block))
            continue;
        if (!isCodeBlock(block))
            return false;
        any = true;
    }
    return any;
}

namespace {
// Code formatting is per paragraph, but one paragraph can hold several lines:
// line breaks (Shift+Enter, or <br> in pasted HTML) and images, each on a line
// of its own. Splits the paragraphs around start and end there, so the lines
// from start to end become paragraphs of their own and formatting them
// leaves the other lines as they are. Returns how far start and end moved.
int isolateLines(QTextCursor &cursor, int start, int end) {
    QTextDocument *document = cursor.document();
    // After the last selected line first, so start stays where it is.
    // A selection ending just after a line break, or starting just before
    // one, takes in no text of the line beyond it (as in blocksIn()).
    auto block = document->findBlock(end);
    QString text = block.text();
    int from = end - block.position();
    if (end > start && from > 0 && text.at(from - 1) == QChar::LineSeparator)
        --from;
    for (int i = from; i < text.size(); ++i) {
        if (i == 0)
            continue;
        if (text.at(i) == QChar::LineSeparator) {
            cursor.setPosition(block.position() + i);
            cursor.deleteChar();
            cursor.insertBlock();
            break;
        }
        if (text.at(i) == QChar::ObjectReplacementCharacter) {
            cursor.setPosition(block.position() + i);
            cursor.insertBlock();
            break;
        }
    }
    block = document->findBlock(start);
    text = block.text();
    from = start - block.position();
    if (end > start && from < text.size() && text.at(from) == QChar::LineSeparator)
        ++from;
    for (int i = std::min(from, int(text.size())) - 1; i >= 0; --i) {
        if (text.at(i) == QChar::LineSeparator) {
            cursor.setPosition(block.position() + i);
            cursor.deleteChar();
            cursor.insertBlock();
            return 0;
        }
        if (text.at(i) == QChar::ObjectReplacementCharacter) {
            if (i + 1 >= text.size())
                return 0;
            cursor.setPosition(block.position() + i + 1);
            cursor.insertBlock();
            return 1;
        }
    }
    return 0;
}
} // namespace

void TextFormatter::toggleCode(QQuickTextDocument *quickDocument, int start,
                               int end) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (blocksIn(document, start, end).isEmpty())
        return;
    const bool code = !codeActive(quickDocument, start, end);
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    const int moved = isolateLines(cursor, start, end);
    const auto blocks = blocksIn(document, start + moved, end + moved);
    for (const auto &block : blocks) {
        if (isImageOnly(block))
            continue;
        // Code is not a list or checklist item; take it out of any list
        // first, checkbox included.
        if (code) {
            if (auto *list = block.textList())
                list->remove(block);
            QTextCursor paragraph(block);
            auto format = paragraph.blockFormat();
            format.setIndent(0);
            format.setMarker(QTextBlockFormat::MarkerType::NoMarker);
            paragraph.setBlockFormat(format);
        }
        setCode(block, code);
    }
    cursor.endEditBlock();
}

bool TextFormatter::endEmptyCodeLine(QQuickTextDocument *quickDocument,
                                     int position) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount())
        return false;
    const auto block = document->findBlock(position);
    if (!isCodeBlock(block) || !block.text().isEmpty() ||
        (block.next().isValid() && isCodeBlock(block.next())))
        return false;
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    setCode(block, false);
    cursor.endEditBlock();
    return true;
}

int TextFormatter::lineAfterCode(QQuickTextDocument *quickDocument) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || !isCodeBlock(document->lastBlock()))
        return -1;
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    cursor.movePosition(QTextCursor::End);
    // The new paragraph starts as a copy of the code line; setCode() takes
    // the code formatting off again.
    cursor.insertBlock();
    setCode(cursor.block(), false);
    cursor.endEditBlock();
    return cursor.block().position();
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

int TextFormatter::checkState(QQuickTextDocument *quickDocument,
                              int position) const {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount())
        return 0;
    const auto block = document->findBlock(position);
    if (!isChecklistItem(block))
        return 0;
    return block.blockFormat().marker() == QTextBlockFormat::MarkerType::Checked
               ? 2
               : 1;
}

bool TextFormatter::toggleCheck(QQuickTextDocument *quickDocument,
                                int position) {
    const int state = checkState(quickDocument, position);
    if (state == 0)
        return false;
    auto *document = quickDocument->textDocument();
    const auto block = document->findBlock(position);
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    setMarker(block, state == 2 ? QTextBlockFormat::MarkerType::Unchecked
                                : QTextBlockFormat::MarkerType::Checked);
    setStruckOut(block, state != 2);
    cursor.endEditBlock();
    return true;
}

void TextFormatter::uncheckNewItem(QQuickTextDocument *quickDocument,
                                   int position) {
    // Enter copies the item it splits, tick and all; a new item starts open.
    if (checkState(quickDocument, position) != 2)
        return;
    const auto block = quickDocument->textDocument()->findBlock(position);
    if (block.text().isEmpty()) {
        setMarker(block, QTextBlockFormat::MarkerType::Unchecked);
        setStruckOut(block, false);
    }
}

namespace {
// Bullets change shape and numbers change style with each level, as in most
// editors, so nested levels are easy to tell apart.
QTextListFormat::Style styleForLevel(bool numbered, int level) {
    static const QTextListFormat::Style bullets[] = {
        QTextListFormat::ListDisc, QTextListFormat::ListCircle,
        QTextListFormat::ListSquare};
    static const QTextListFormat::Style numbers[] = {
        QTextListFormat::ListDecimal, QTextListFormat::ListLowerAlpha,
        QTextListFormat::ListLowerRoman};
    const int index = (qMax(1, level) - 1) % 3;
    return numbered ? numbers[index] : bullets[index];
}
} // namespace

bool TextFormatter::indentList(QQuickTextDocument *quickDocument, int start,
                               int end, int delta) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    const auto blocks = blocksIn(document, start, end);
    if (blocks.isEmpty() || delta == 0)
        return false;
    for (const auto &block : blocks) {
        if (!block.textList())
            return false;
    }
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    for (const auto &block : blocks) {
        auto *list = block.textList();
        const auto format = list->format();
        const bool numbered = !isBullet(format.style());
        const int level = qMin(format.indent() + delta, 8);
        const auto marker = block.blockFormat().marker();
        list->remove(block);
        QTextCursor paragraph(block);
        auto blockFormat = paragraph.blockFormat();
        blockFormat.setIndent(0);
        paragraph.setBlockFormat(blockFormat);
        if (level < 1) {
            setMarker(block, QTextBlockFormat::MarkerType::NoMarker);
            continue;
        }
        // Join the list the item above has at this level, so consecutive
        // items share one list and keep counting.
        QTextList *target = nullptr;
        for (auto above = block.previous(); above.isValid(); above = above.previous()) {
            auto *candidate = above.textList();
            if (!candidate)
                break;
            if (candidate->format().indent() == level) {
                target = candidate;
                break;
            }
            if (candidate->format().indent() < level)
                break;
        }
        if (target) {
            target->add(block);
        } else {
            QTextListFormat nested;
            nested.setIndent(level);
            nested.setStyle(styleForLevel(numbered, level));
            paragraph.createList(nested);
        }
        setMarker(block, marker);
    }
    cursor.endEditBlock();
    return true;
}

QVariantList TextFormatter::findAll(QQuickTextDocument *quickDocument,
                                    const QString &text,
                                    bool caseSensitive) const {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    QVariantList matches;
    if (!document || text.isEmpty())
        return matches;
    const QTextDocument::FindFlags flags =
        caseSensitive ? QTextDocument::FindCaseSensitively
                      : QTextDocument::FindFlags();
    QTextCursor cursor(document);
    while (true) {
        cursor = document->find(text, cursor, flags);
        if (cursor.isNull() || matches.size() >= 10000)
            break;
        matches.append(QVariantMap{{QStringLiteral("start"), cursor.selectionStart()},
                                   {QStringLiteral("end"), cursor.selectionEnd()}});
    }
    return matches;
}

bool TextFormatter::replaceRange(QQuickTextDocument *quickDocument, int start,
                                 int end, const QString &text) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || start < 0 || end < start ||
        end >= document->characterCount())
        return false;
    QTextCursor cursor(document);
    cursor.setPosition(start);
    cursor.setPosition(end, QTextCursor::KeepAnchor);
    // insertText keeps the format of the text it replaces.
    cursor.insertText(text);
    return true;
}

int TextFormatter::replaceAll(QQuickTextDocument *quickDocument,
                              const QString &text, const QString &replacement,
                              bool caseSensitive) {
    const auto matches = findAll(quickDocument, text, caseSensitive);
    if (matches.isEmpty())
        return 0;
    QTextCursor cursor(quickDocument->textDocument());
    cursor.beginEditBlock();
    // Last first, so earlier positions stay valid.
    for (auto it = matches.crbegin(); it != matches.crend(); ++it) {
        const auto match = it->toMap();
        replaceRange(quickDocument, match.value(QStringLiteral("start")).toInt(),
                     match.value(QStringLiteral("end")).toInt(), replacement);
    }
    cursor.endEditBlock();
    return int(matches.size());
}

QString TextFormatter::alignmentAt(QQuickTextDocument *quickDocument,
                                   int position) const {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount())
        return QStringLiteral("left");
    const auto alignment =
        document->findBlock(position).blockFormat().alignment();
    if (alignment & Qt::AlignHCenter)
        return QStringLiteral("center");
    if (alignment & Qt::AlignJustify)
        return QStringLiteral("justify");
    if (alignment & Qt::AlignRight)
        return QStringLiteral("right");
    return QStringLiteral("left");
}

void TextFormatter::setAlignment(QQuickTextDocument *quickDocument, int start,
                                 int end, const QString &alignment) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    const auto blocks = blocksIn(document, start, end);
    Qt::Alignment value = Qt::AlignLeft;
    if (alignment == u"center")
        value = Qt::AlignHCenter;
    else if (alignment == u"right")
        value = Qt::AlignRight;
    else if (alignment == u"justify")
        value = Qt::AlignJustify;
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    for (const auto &block : blocks) {
        QTextCursor paragraph(block);
        auto format = paragraph.blockFormat();
        format.setAlignment(value);
        paragraph.setBlockFormat(format);
    }
    cursor.endEditBlock();
}

QVariantList TextFormatter::checkBoxes(QQuickTextDocument *quickDocument) const {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    QVariantList boxes;
    if (!document)
        return boxes;
    for (auto block = document->begin(); block.isValid(); block = block.next()) {
        if (!isChecklistItem(block))
            continue;
        boxes.append(QVariantMap{
            {QStringLiteral("position"), block.position()},
            {QStringLiteral("checked"),
             block.blockFormat().marker() == QTextBlockFormat::MarkerType::Checked}});
    }
    return boxes;
}

int TextFormatter::insertImageParagraph(QQuickTextDocument *quickDocument,
                                        int position, const QString &name,
                                        int width) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount() ||
        name.isEmpty())
        return -1;
    QTextCursor cursor(document);
    cursor.setPosition(position);
    cursor.beginEditBlock();
    // The image gets a plain paragraph of its own, so paragraph formats (code
    // blocks, lists, alignment) of the text around it never take it along.
    if (cursor.positionInBlock() > 0)
        cursor.insertBlock(QTextBlockFormat(), QTextCharFormat());
    else {
        cursor.setBlockFormat(QTextBlockFormat());
        if (auto *list = cursor.currentList())
            list->remove(cursor.block());
    }
    QTextImageFormat image;
    image.setName(name);
    if (width > 0)
        image.setWidth(width);
    cursor.insertImage(image);
    // Text after the image, if any, moves to the next paragraph with the caret.
    cursor.insertBlock(QTextBlockFormat(), QTextCharFormat());
    cursor.endEditBlock();
    return cursor.position();
}

bool TextFormatter::separateImages(QQuickTextDocument *quickDocument) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document)
        return false;
    // Line breaks (U+2028) next to images become paragraph breaks. Collected
    // first, then applied from the end so earlier positions stay valid.
    QList<int> breaks;
    for (auto block = document->begin(); block.isValid(); block = block.next()) {
        for (auto it = block.begin(); !it.atEnd(); ++it) {
            const auto fragment = it.fragment();
            if (!fragment.charFormat().isImageFormat())
                continue;
            const QString text = block.text();
            for (int i = 0; i < fragment.length(); ++i) {
                const int inBlock = fragment.position() - block.position() + i;
                if (inBlock > 0 && text.at(inBlock - 1) == QChar::LineSeparator)
                    breaks.append(block.position() + inBlock - 1);
                if (inBlock + 1 < text.size() && text.at(inBlock + 1) == QChar::LineSeparator)
                    breaks.append(block.position() + inBlock + 1);
            }
        }
    }
    if (breaks.isEmpty())
        return false;
    std::sort(breaks.begin(), breaks.end());
    breaks.erase(std::unique(breaks.begin(), breaks.end()), breaks.end());
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    for (auto it = breaks.crbegin(); it != breaks.crend(); ++it) {
        QTextCursor at(document);
        at.setPosition(*it);
        at.setPosition(*it + 1, QTextCursor::KeepAnchor);
        at.removeSelectedText();
        at.insertBlock();
    }
    cursor.endEditBlock();
    return true;
}

bool TextFormatter::clearEmptyFormatting(QQuickTextDocument *quickDocument) {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || document->characterCount() > 1)
        return false;
    const auto block = document->begin();
    const bool formatted = block.textList() || isCodeBlock(block) ||
                           block.blockFormat().hasProperty(QTextFormat::BlockAlignment) ||
                           block.charFormat().fontFixedPitch() ||
                           block.charFormat().fontStrikeOut();
    if (!formatted)
        return false;
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    if (auto *list = block.textList())
        list->remove(block);
    cursor.setBlockFormat(QTextBlockFormat());
    cursor.setBlockCharFormat(QTextCharFormat());
    cursor.setCharFormat(QTextCharFormat());
    cursor.endEditBlock();
    return true;
}

void TextFormatter::prepare(QQuickTextDocument *quickDocument) {
    if (auto *document = quickDocument ? quickDocument->textDocument() : nullptr)
        document->setIndentWidth(22);
}

int TextFormatter::listLevel(QQuickTextDocument *quickDocument, int position) const {
    auto *document = quickDocument ? quickDocument->textDocument() : nullptr;
    if (!document || position < 0 || position >= document->characterCount())
        return 0;
    const auto *list = document->findBlock(position).textList();
    return list ? list->format().indent() : 0;
}
