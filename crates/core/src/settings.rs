use std::fmt;
use std::str::FromStr;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ThemePreference {
    #[default]
    System,
    Light,
    Dark,
    /// Warm, paper-like light theme.
    Sepia,
    /// Dark theme on pure black, for OLED screens.
    Black,
}

impl ThemePreference {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
            Self::Sepia => "sepia",
            Self::Black => "black",
        }
    }
}

impl fmt::Display for ThemePreference {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for ThemePreference {
    type Err = std::convert::Infallible;

    fn from_str(s: &str) -> std::result::Result<Self, Self::Err> {
        Ok(match s.trim().to_ascii_lowercase().as_str() {
            "light" => Self::Light,
            "dark" => Self::Dark,
            "sepia" => Self::Sepia,
            "black" => Self::Black,
            _ => Self::System,
        })
    }
}

/// The accent colour when none is chosen.
pub const DEFAULT_ACCENT: &str = "#6366f1";

/// A "#rrggbb" colour in lower case, or None when the text is not one.
pub fn normalize_accent(value: &str) -> Option<String> {
    let value = value.trim();
    let hex = value.strip_prefix('#')?;
    (hex.len() == 6 && hex.chars().all(|c| c.is_ascii_hexdigit()))
        .then(|| format!("#{}", hex.to_ascii_lowercase()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn themes_and_accents_parse() {
        for theme in ["system", "light", "dark", "sepia", "black"] {
            assert_eq!(theme.parse::<ThemePreference>().unwrap().as_str(), theme);
        }
        assert_eq!(
            "neon".parse::<ThemePreference>().unwrap(),
            ThemePreference::System
        );
        assert_eq!(normalize_accent(" #0EA5E9 ").as_deref(), Some("#0ea5e9"));
        for bad in ["0ea5e9", "#0ea5e", "#gggggg", "red", ""] {
            assert!(normalize_accent(bad).is_none(), "{bad}");
        }
    }
}
