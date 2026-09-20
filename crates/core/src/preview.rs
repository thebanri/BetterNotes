//! Plain-text previews for note bodies.
//!
//! Rich-text notes are stored as the HTML document Qt's text engine produces,
//! so a raw `substr` of the body is mostly `<!DOCTYPE …><head><style>…`. List
//! rows, search results, the CLI and IPC all want readable text, so the
//! conversion lives here rather than in any one presentation layer.

/// Elements whose text content is markup or metadata, never note text.
const SKIPPED_ELEMENTS: [&str; 4] = ["script", "style", "head", "title"];

/// Elements that end a line of text; they become whitespace, not nothing, so
/// that `<p>one</p><p>two</p>` previews as `one two` rather than `onetwo`.
const BREAKING_ELEMENTS: [&str; 17] = [
    "p",
    "br",
    "div",
    "li",
    "tr",
    "td",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "blockquote",
    "pre",
    "ul",
    "ol",
    "hr",
];

/// Converts stored note content to plain text, keeping paragraph breaks.
///
/// Input is treated as untrusted: unterminated tags and unknown entities are
/// dropped rather than passed through, so markup can never reach a caller that
/// renders its result as rich text.
pub fn to_plain_text(content: &str) -> String {
    if !content.contains('<') {
        return decode_entities(content);
    }
    let mut out = String::with_capacity(content.len());
    let mut rest = content;
    loop {
        let Some(open) = rest.find('<') else {
            out.push_str(&decode_entities(rest));
            break;
        };
        out.push_str(&decode_entities(&rest[..open]));
        let after = &rest[open + 1..];
        let Some(close) = after.find('>') else {
            // An unterminated tag means the remainder is markup, not text.
            break;
        };
        let tag = &after[..close];
        let name = element_name(tag);
        let body = &after[close + 1..];
        if !tag.starts_with('/') && !tag.ends_with('/') && SKIPPED_ELEMENTS.contains(&name.as_str())
        {
            rest = skip_element(body, &name);
            continue;
        }
        if BREAKING_ELEMENTS.contains(&name.as_str()) {
            out.push('\n');
        }
        rest = body;
    }
    out
}

/// Builds a single-line preview of at most `max_chars` characters.
///
/// Runs of whitespace collapse to one space so multi-paragraph notes stay
/// readable on one line. An ellipsis marks content that did not fit.
pub fn plain_preview(content: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }
    let text = to_plain_text(content);
    let mut preview = String::new();
    let mut taken = 0usize;
    let mut pending_space = false;
    let mut truncated = false;
    for character in text.chars() {
        if character.is_whitespace() {
            pending_space = !preview.is_empty();
            continue;
        }
        if pending_space {
            if taken == max_chars {
                truncated = true;
                break;
            }
            preview.push(' ');
            taken += 1;
            pending_space = false;
        }
        if taken == max_chars {
            truncated = true;
            break;
        }
        preview.push(character);
        taken += 1;
    }
    if truncated {
        preview.push('…');
    }
    preview
}

/// Lowercased element name of a tag body, without the `/` of a closing tag.
fn element_name(tag: &str) -> String {
    tag.trim_start_matches('/')
        .chars()
        .take_while(|character| character.is_ascii_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

/// Returns the remainder after this element's closing tag, or an empty string
/// when the document never closes it.
fn skip_element<'a>(body: &'a str, name: &str) -> &'a str {
    let mut rest = body;
    loop {
        let Some(open) = rest.find('<') else {
            return "";
        };
        let after = &rest[open + 1..];
        let Some(close) = after.find('>') else {
            return "";
        };
        let tag = &after[..close];
        if tag.starts_with('/') && element_name(tag) == name {
            return &after[close + 1..];
        }
        rest = &after[close + 1..];
    }
}

/// Resolves the entities Qt's HTML writer emits; anything else is dropped.
fn decode_entities(text: &str) -> String {
    if !text.contains('&') {
        return text.to_string();
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    loop {
        let Some(start) = rest.find('&') else {
            out.push_str(rest);
            break;
        };
        out.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        // A bare `&` is common in plain text; only treat it as an entity when a
        // short, well-formed reference follows.
        let Some(end) = after.find(';').filter(|end| *end <= 10) else {
            out.push('&');
            rest = after;
            continue;
        };
        match resolve_entity(&after[..end]) {
            Some(resolved) => out.push(resolved),
            None => out.push('\u{fffd}'),
        }
        rest = &after[end + 1..];
    }
    out
}

fn resolve_entity(name: &str) -> Option<char> {
    match name {
        "amp" => return Some('&'),
        "lt" => return Some('<'),
        "gt" => return Some('>'),
        "quot" => return Some('"'),
        "apos" => return Some('\''),
        "nbsp" => return Some(' '),
        _ => {}
    }
    let digits = name.strip_prefix('#')?;
    let code = match digits.strip_prefix(['x', 'X']) {
        Some(hex) => u32::from_str_radix(hex, 16).ok()?,
        None => digits.parse().ok()?,
    };
    char::from_u32(code)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_content_is_returned_unchanged() {
        assert_eq!(to_plain_text("just a note"), "just a note");
        assert_eq!(plain_preview("just a note", 40), "just a note");
    }

    #[test]
    fn qt_rich_text_document_previews_as_readable_text() {
        let document = concat!(
            "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0//EN\" \"http://www.w3.org/TR/REC-html40/strict.dtd\">",
            "<html><head><meta name=\"qrichtext\" content=\"1\" />",
            "<style type=\"text/css\">p, li { white-space: pre-wrap; }</style></head>",
            "<body style=\" font-family:'Noto Sans'; font-size:13px;\">",
            "<p>Shopping <b>list</b></p><p>milk &amp; bread</p></body></html>",
        );
        assert_eq!(plain_preview(document, 80), "Shopping list milk & bread");
    }

    #[test]
    fn breaking_elements_separate_words_and_runs_of_space_collapse() {
        assert_eq!(plain_preview("<p>one</p><p>two</p>", 40), "one two");
        assert_eq!(plain_preview("a  \n\t  b", 40), "a b");
        assert_eq!(plain_preview("<div>a</div><br/>b", 40), "a b");
    }

    #[test]
    fn preview_truncates_on_a_character_budget() {
        assert_eq!(plain_preview("abcdefghij", 4), "abcd…");
        assert_eq!(plain_preview("abcd", 4), "abcd");
        assert_eq!(plain_preview("ab cd ef", 5), "ab cd…");
        assert_eq!(plain_preview("anything", 0), "");
    }

    #[test]
    fn multibyte_content_is_not_split_mid_character() {
        assert_eq!(plain_preview("günaydın dünya", 8), "günaydın…");
        assert_eq!(plain_preview("<p>çğıöşü</p>", 40), "çğıöşü");
    }

    #[test]
    fn markup_never_survives_into_the_preview() {
        // Truncated documents and stray angle brackets are common in stored
        // content; none of it may reach a caller that renders rich text.
        assert_eq!(plain_preview("<p>text<b", 40), "text");
        assert_eq!(plain_preview("<style>p{color:red}</style>hi", 40), "hi");
        assert_eq!(plain_preview("<script>alert(1)</script>hi", 40), "hi");
        assert_eq!(
            plain_preview("&lt;b&gt;not bold&lt;/b&gt;", 40),
            "<b>not bold</b>"
        );
        assert!(!plain_preview("<img src=\"x\"/>caption", 40).contains('<'));
    }

    #[test]
    fn unclosed_skipped_element_drops_the_remainder() {
        assert_eq!(plain_preview("visible<style>p{}", 40), "visible");
    }

    #[test]
    fn entities_resolve_and_unknown_references_do_not_leak() {
        assert_eq!(to_plain_text("&#65;&#x42;"), "AB");
        assert_eq!(to_plain_text("a &nbsp; b"), "a   b");
        assert_eq!(to_plain_text("Tom & Jerry"), "Tom & Jerry");
        assert_eq!(to_plain_text("&bogus;"), "\u{fffd}");
    }
}
