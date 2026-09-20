//! Freedesktop desktop notifications interface.

use crate::Result;
use std::process::Command;

pub struct NotificationService;

impl NotificationService {
    /// Dispatches a notification using standard Freedesktop mechanisms (`notify-send`).
    /// Fails gracefully if no notification daemon is active or notify-send is absent.
    pub fn notify(title: &str, body: &str) -> Result<bool> {
        let status = Command::new("notify-send")
            .arg("--app-name=BetterNotes")
            .arg("--icon=document-notes")
            .arg(title)
            .arg(body)
            .status();

        match status {
            Ok(s) => Ok(s.success()),
            Err(e) => {
                eprintln!("BetterNotes: notification service notice: {e}");
                Ok(false)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn notification_service_does_not_panic() {
        let _ = NotificationService::notify("Test", "Testing notification dispatch");
    }
}
