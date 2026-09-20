use crate::{Error, Result};

/// Normal, expanded client geometry in Qt logical pixels. Position is optional
/// because Wayland does not expose reliable global window coordinates.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WindowState {
    pub position: Option<(i32, i32)>,
    pub width: i32,
    pub height: i32,
    pub screen: String,
    pub collapsed: bool,
    pub open: bool,
}

impl Default for WindowState {
    fn default() -> Self {
        Self {
            position: None,
            width: 380,
            height: 360,
            screen: String::new(),
            collapsed: false,
            open: false,
        }
    }
}

impl WindowState {
    pub fn validate(&self) -> Result<()> {
        if !(240..=16384).contains(&self.width)
            || !(180..=16384).contains(&self.height)
            || self.screen.len() > 4096
            || self.position.is_some_and(|(x, y)| {
                !(-1_000_000..=1_000_000).contains(&x) || !(-1_000_000..=1_000_000).contains(&y)
            })
        {
            return Err(Error::InvalidWindowState);
        }
        Ok(())
    }
}
