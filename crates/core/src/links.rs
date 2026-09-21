//! Deciding which links in a note may be opened.
//!
//! Note content is untrusted: it can be imported, pasted or synced in, and a
//! stored anchor can name any scheme. Clicking a link hands it to the desktop's
//! opener, so only schemes that open a web page or a mail draft are allowed.
//! `file:`, `javascript:`, `data:` and custom URL handlers never open.

/// Returns the URL to hand to the desktop opener, or `None` when the link must
/// not be opened. A bare `www.` address is opened over https.
pub fn external_url(link: &str) -> Option<String> {
    let link = link.trim();
    if link.is_empty() || link.chars().any(|c| c.is_control() || c.is_whitespace()) {
        return None;
    }
    let lower = link.to_ascii_lowercase();
    for scheme in ["https://", "http://"] {
        if let Some(rest) = lower.strip_prefix(scheme) {
            // A web link needs a host; "https:///etc/passwd" is not one.
            return (!rest.is_empty() && !rest.starts_with('/')).then(|| link.to_string());
        }
    }
    if let Some(address) = lower.strip_prefix("mailto:") {
        return address.contains('@').then(|| link.to_string());
    }
    if let Some(rest) = lower.strip_prefix("www.") {
        return (!rest.is_empty()).then(|| format!("https://{link}"));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn web_and_mail_links_open() {
        assert_eq!(
            external_url("https://example.com/a?b=c").as_deref(),
            Some("https://example.com/a?b=c")
        );
        assert_eq!(
            external_url("HTTP://Example.com").as_deref(),
            Some("HTTP://Example.com")
        );
        assert_eq!(
            external_url("mailto:someone@example.com").as_deref(),
            Some("mailto:someone@example.com")
        );
        assert_eq!(
            external_url("  www.example.com  ").as_deref(),
            Some("https://www.example.com")
        );
    }

    #[test]
    fn other_schemes_never_open() {
        for link in [
            "file:///etc/passwd",
            "javascript:alert(1)",
            "data:text/html,<script>",
            "vscode://open?file=x",
            "ftp://example.com",
            "/home/user/script.sh",
            "example.com",
        ] {
            assert_eq!(external_url(link), None, "{link} must not open");
        }
    }

    #[test]
    fn malformed_links_never_open() {
        for link in [
            "",
            "https://",
            "https:///etc/passwd",
            "mailto:",
            "www.",
            "https://a b",
            "https://a\nb",
        ] {
            assert_eq!(external_url(link), None, "{link:?} must not open");
        }
    }
}
