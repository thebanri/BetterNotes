#pragma once

#include <QColor>
#include <QObject>
#include <QQuickTextDocument>
#include <QUrl>
#include <QVariantList>
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
    // Code blocks: paragraphs in a monospace font on a grey background, which
    // survives the note's HTML. Enter on a line holding only ``` (optionally
    // with a language name) starts a code block there, or inside one ends it.
    // Returns the caret position, or -1 when the line is not a fence.
    Q_INVOKABLE int codeFence(QQuickTextDocument *document, int position);
    Q_INVOKABLE bool codeActive(QQuickTextDocument *document, int start,
                                int end) const;
    // Makes the paragraphs from start to end code, or plain text again.
    Q_INVOKABLE void toggleCode(QQuickTextDocument *document, int start,
                                int end);
    // Restores the font of empty code lines, which HTML does not keep, so text
    // typed there after reopening a note is code too.
    Q_INVOKABLE void restoreCodeFont(QQuickTextDocument *document);
    // Each run of consecutive code paragraphs as {start, end} positions. Qt
    // Quick does not paint paragraph backgrounds, so the editor draws the
    // code boxes itself.
    Q_INVOKABLE QVariantList codeBlocks(QQuickTextDocument *document) const;
    // Checklists: 0 for no checkbox at position, 1 open, 2 ticked.
    Q_INVOKABLE int checkState(QQuickTextDocument *document, int position) const;
    Q_INVOKABLE bool toggleCheck(QQuickTextDocument *document, int position);
    // A new item made by Enter on a ticked one starts unticked.
    Q_INVOKABLE void uncheckNewItem(QQuickTextDocument *document, int position);
    // Moves list items a level in (delta 1) or out (-1); out of the first
    // level ends the list. Returns false when a paragraph is not a list item.
    Q_INVOKABLE bool indentList(QQuickTextDocument *document, int start, int end,
                                int delta);
    // Every occurrence of text as {start, end}, matched as Qt matches it, so
    // positions stay right for letters whose case changes their length.
    Q_INVOKABLE QVariantList findAll(QQuickTextDocument *document,
                                     const QString &text,
                                     bool caseSensitive) const;
    Q_INVOKABLE bool replaceRange(QQuickTextDocument *document, int start,
                                  int end, const QString &text);
    Q_INVOKABLE int replaceAll(QQuickTextDocument *document, const QString &text,
                               const QString &replacement, bool caseSensitive);
    // Paragraph alignment: "left", "center", "right" or "justify".
    Q_INVOKABLE QString alignmentAt(QQuickTextDocument *document,
                                    int position) const;
    Q_INVOKABLE void setAlignment(QQuickTextDocument *document, int start,
                                  int end, const QString &alignment);
    // Every checklist item as {position, checked}, for drawing its box.
    Q_INVOKABLE QVariantList checkBoxes(QQuickTextDocument *document) const;
    // Inserts an image as a paragraph of its own; returns the caret position.
    Q_INVOKABLE int insertImageParagraph(QQuickTextDocument *document,
                                         int position, const QString &name,
                                         int width);
    // Gives images that share a paragraph with text (older notes) their own.
    Q_INVOKABLE bool separateImages(QQuickTextDocument *document);
    // After everything is deleted, the empty paragraph loses list, checklist,
    // code and alignment formatting. Returns whether anything changed.
    Q_INVOKABLE bool clearEmptyFormatting(QQuickTextDocument *document);
    // Document settings the editor needs, such as a compact list indent.
    Q_INVOKABLE void prepare(QQuickTextDocument *document);
    // The list level of the paragraph at position: 0 outside a list, 1 for a
    // top-level item, 2 for a sub-item and so on.
    Q_INVOKABLE int listLevel(QQuickTextDocument *document, int position) const;
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
