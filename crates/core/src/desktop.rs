//! Desktop environment and display server capability detection for Linux desktop integration.

use std::env;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DisplayServer {
    Wayland,
    X11,
    Offscreen,
    Unknown,
}

impl DisplayServer {
    pub fn detect() -> Self {
        if let Ok(platform) = env::var("QT_QPA_PLATFORM") {
            if platform == "offscreen" {
                return Self::Offscreen;
            }
            if platform.starts_with("wayland") {
                return Self::Wayland;
            }
            if platform == "xcb" {
                return Self::X11;
            }
        }
        if env::var_os("WAYLAND_DISPLAY").is_some() {
            Self::Wayland
        } else if env::var_os("DISPLAY").is_some() {
            Self::X11
        } else {
            Self::Unknown
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Wayland => "Wayland",
            Self::X11 => "X11",
            Self::Offscreen => "Offscreen (Headless)",
            Self::Unknown => "Unknown",
        }
    }

    pub fn can_position_windows(&self) -> bool {
        // Wayland intentionally prohibits clients from setting absolute screen coordinates.
        // X11 and offscreen testing support explicit geometry positioning.
        matches!(self, Self::X11 | Self::Offscreen)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DesktopEnvironment {
    KdePlasma,
    Gnome,
    Xfce,
    Cinnamon,
    Mate,
    Budgie,
    Hyprland,
    Sway,
    Other(String),
}

impl DesktopEnvironment {
    /// Whether sticky notes can be kept beneath ordinary windows here. X11
    /// window managers honour the keep-below hint directly. Wayland has no
    /// protocol for it, so only KDE Plasma works, through the KWin script in
    /// [`Self::setup_window_manager_integration`].
    pub fn supports_note_layers(&self, display: DisplayServer) -> bool {
        match display {
            DisplayServer::X11 => true,
            DisplayServer::Wayland => matches!(self, Self::KdePlasma),
            DisplayServer::Offscreen | DisplayServer::Unknown => false,
        }
    }

    pub fn detect() -> Self {
        if env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some() {
            return Self::Hyprland;
        }
        if env::var_os("SWAYSOCK").is_some() {
            return Self::Sway;
        }

        let desktop = env::var("XDG_CURRENT_DESKTOP")
            .or_else(|_| env::var("DESKTOP_SESSION"))
            .unwrap_or_default()
            .to_uppercase();

        if desktop.contains("KDE") || desktop.contains("PLASMA") {
            Self::KdePlasma
        } else if desktop.contains("GNOME") {
            Self::Gnome
        } else if desktop.contains("XFCE") {
            Self::Xfce
        } else if desktop.contains("CINNAMON") {
            Self::Cinnamon
        } else if desktop.contains("MATE") {
            Self::Mate
        } else if desktop.contains("BUDGIE") {
            Self::Budgie
        } else if desktop.contains("HYPRLAND") {
            Self::Hyprland
        } else if desktop.contains("SWAY") {
            Self::Sway
        } else if !desktop.is_empty() {
            Self::Other(desktop)
        } else {
            Self::Other("Generic / Standalone WM".into())
        }
    }

    pub fn name(&self) -> &str {
        match self {
            Self::KdePlasma => "KDE Plasma",
            Self::Gnome => "GNOME",
            Self::Xfce => "XFCE",
            Self::Cinnamon => "Cinnamon",
            Self::Mate => "MATE",
            Self::Budgie => "Budgie",
            Self::Hyprland => "Hyprland",
            Self::Sway => "Sway",
            Self::Other(name) => name.as_str(),
        }
    }

    pub fn is_tiling(&self) -> bool {
        matches!(self, Self::Hyprland | Self::Sway)
    }

    pub fn window_rule_hint(&self) -> Option<&'static str> {
        match self {
            Self::Hyprland => Some(
                "windowrule = float, ^(betternotes)$\nwindowrule = size 380 360, ^(betternotes)$",
            ),
            Self::Sway => Some("for_window [app_id=\"betternotes\"] floating enable"),
            _ => None,
        }
    }

    pub fn tray_notes(&self) -> &'static str {
        match self {
            Self::Gnome => {
                "GNOME requires the 'AppIndicator and KStatusNotifierItem Support' extension for tray icons."
            }
            Self::Hyprland | Self::Sway => {
                "Requires a status bar with SNI tray support (e.g. Waybar with 'tray' module enabled)."
            }
            _ => "StatusNotifierItem (Freedesktop SNI) supported natively.",
        }
    }

    /// Automatically registers window manager rules and scripts to ensure sticky notes
    /// do not appear as windows in the taskbar or switcher, and sit in the layer
    /// their caption asks for.
    pub fn setup_window_manager_integration(&self) {
        if matches!(self, Self::KdePlasma) {
            setup_kde_plasma_taskbar_integration();
        }
    }
}

// Layer markers: a sticky note appends an invisible character to its window
// caption -- U+2063 for keep-below, U+2064 for keep-above (pinned). Wayland
// gives a client no way to choose its own layer, and the caption is the only
// per-window value a KWin script can read, so the note states its layer there.
// Must match `layerMarker` in StickyNote.qml.
fn setup_kde_plasma_taskbar_integration() {
    let script_content = r#"
// Talks to WindowPlacement in the app (app/src/window_placement.h).
var PLACEMENT = ["org.betternotes.BetterNotes", "/Placement",
                 "org.betternotes.BetterNotes.Placement"];

// X11 reports the binary name as the window class; Wayland reports the app id.
function isBetterNotes(win) {
    var ids = ["betternotes", "org.betternotes.betternotes"];
    return ids.indexOf((win.resourceClass || "").toLowerCase()) !== -1 ||
        ids.indexOf((win.resourceName || "").toLowerCase()) !== -1;
}

function isNote(win) {
    // Notes shown as desktop widgets are layer-shell surfaces; the app
    // places and stacks those itself.
    if (!win || !win.normalWindow || !isBetterNotes(win)) return false;
    var cap = win.caption || "";
    return cap.indexOf("All notes") === -1 && cap.indexOf("Quick Capture") === -1;
}

// A note's id, written into its caption as invisible Unicode tag digits
// (U+E0030..U+E0039), which arrive here as surrogate pairs.
function noteKey(win) {
    var cap = win.caption || "";
    var key = "";
    for (var i = 0; i + 1 < cap.length; i++) {
        if (cap.charCodeAt(i) !== 0xDB40) continue;
        var digit = cap.charCodeAt(i + 1) - 0xDC30;
        if (digit >= 0 && digit <= 9) { key += digit; i++; }
    }
    return key;
}

function applyLayer(win) {
    var cap = win.caption || "";
    win.skipTaskbar = true;
    win.skipPager = true;
    win.skipSwitcher = true;
    // The note names its layer with an invisible caption marker; no marker
    // means an ordinary window. Re-evaluated on every caption change, so
    // pinning or the global setting takes effect immediately.
    var below = cap.indexOf("⁣") !== -1;
    var above = cap.indexOf("⁤") !== -1;
    if (win.keepBelow !== below) win.keepBelow = below;
    if (win.keepAbove !== above) win.keepAbove = above;
}

// Somewhere a user can still grab the note's header, on a screen that exists
// now: a note saved on a monitor that has since been unplugged is left to
// normal placement instead of disappearing off-screen.
function reachable(x, y, width) {
    var screens = workspace.screens;
    for (var i = 0; i < screens.length; i++) {
        var g = screens[i].geometry;
        if (x + width - 40 >= g.x && x + 40 <= g.x + g.width &&
            y >= g.y && y + 30 <= g.y + g.height) return true;
    }
    return false;
}

function isLibrary(win) {
    return !!win && isBetterNotes(win) && (win.caption || "").indexOf("All notes") !== -1;
}

// Centres a window on the screen the user is working on, inside the area left
// free by panels. KWin's own placement puts a new window in the top-left.
function center(win) {
    var area;
    try {
        area = workspace.clientArea(KWin.PlacementArea, workspace.activeScreen,
                                    workspace.currentDesktop);
    } catch (error) {
        area = workspace.activeScreen.geometry;
    }
    var g = win.frameGeometry;
    win.frameGeometry = {
        x: Math.round(area.x + Math.max(0, (area.width - g.width) / 2)),
        y: Math.round(area.y + Math.max(0, (area.height - g.height) / 2)),
        width: g.width,
        height: g.height
    };
}

function report(win) {
    var key = noteKey(win);
    if (!key) return;
    var g = win.frameGeometry;
    callDBus(PLACEMENT[0], PLACEMENT[1], PLACEMENT[2], "Moved",
             key, Math.round(g.x), Math.round(g.y));
}

function restore(win) {
    var key = noteKey(win);
    if (!key) return;
    callDBus(PLACEMENT[0], PLACEMENT[1], PLACEMENT[2], "Placement", key,
             function(position) {
        var parts = ("" + (position || "")).split(",");
        var g = win.frameGeometry;
        if (parts.length === 2) {
            var x = parseInt(parts[0], 10), y = parseInt(parts[1], 10);
            if (!isNaN(x) && !isNaN(y) && reachable(x, y, g.width)) {
                win.frameGeometry = {x: x, y: y, width: g.width, height: g.height};
                return;
            }
        }
        // Nothing usable saved: a new note starts in the middle of the screen,
        // and that becomes its saved position.
        center(win);
        report(win);
    });
}

function watch(win, isNew) {
    if (!win) return;
    // The library keeps no position on Wayland; open it centred.
    if (isNew && isLibrary(win)) center(win);
    if (isNote(win)) {
        applyLayer(win);
        // Only a newly opened note is moved; notes already on screen when this
        // script (re)loads stay where the user has them.
        if (isNew) restore(win);
        win.interactiveMoveResizeFinished.connect(function() { report(win); });
    }
    // "Arrange notes": the app gives each note a new position and flips an
    // invisible caption marker (U+2062); the flip asks for the position again.
    var arranged = (win.caption || "").indexOf("\u2062") !== -1;
    win.captionChanged.connect(function() {
        if (!isNote(win)) return;
        applyLayer(win);
        var now = (win.caption || "").indexOf("\u2062") !== -1;
        if (now !== arranged) {
            arranged = now;
            restore(win);
        }
    });
}

workspace.windowAdded.connect(function(win) { watch(win, true); });
var existing = workspace.windowList();
for (var i = 0; i < existing.length; i++) {
    watch(existing[i], false);
}
"#;

    if let Ok(data_dir) = crate::paths::data_directory(
        std::env::var_os("XDG_DATA_HOME").as_deref(),
        std::env::var_os("HOME").as_deref(),
    ) {
        let script_path = data_dir.join("kwin_skip_taskbar.js");
        if std::fs::write(&script_path, script_content).is_ok() {
            // KWin keeps a loaded script until it is unloaded, and loading the
            // same path again returns the old copy. Unload first so a newer
            // version of this script replaces it.
            let _ = std::process::Command::new("busctl")
                .args([
                    "--user",
                    "call",
                    "org.kde.KWin",
                    "/Scripting",
                    "org.kde.kwin.Scripting",
                    "unloadScript",
                    "s",
                    script_path.to_str().unwrap_or_default(),
                ])
                .output();
            if let Ok(out) = std::process::Command::new("busctl")
                .args([
                    "--user",
                    "call",
                    "org.kde.KWin",
                    "/Scripting",
                    "org.kde.kwin.Scripting",
                    "loadScript",
                    "s",
                    script_path.to_str().unwrap_or_default(),
                ])
                .output()
            {
                if out.status.success() {
                    // Start every loaded script that is not running yet rather
                    // than calling run() on /Scripting/Script<id>: KWin reuses
                    // the id of a script it is still tearing down, and run()
                    // can then reach that old object and silently do nothing.
                    let _ = std::process::Command::new("busctl")
                        .args([
                            "--user",
                            "call",
                            "org.kde.KWin",
                            "/Scripting",
                            "org.kde.kwin.Scripting",
                            "start",
                        ])
                        .status();
                }
            }
        }
    }

    let kread = std::process::Command::new("kreadconfig6")
        .args([
            "--file",
            "kwinrulesrc",
            "--group",
            "General",
            "--key",
            "rules",
        ])
        .output();

    if let Ok(out) = kread {
        let existing_rules = String::from_utf8_lossy(&out.stdout).trim().to_string();
        let mut rules: Vec<String> = existing_rules
            .split(',')
            .filter(|s| !s.trim().is_empty())
            .map(|s| s.trim().to_string())
            .collect();

        if !rules.iter().any(|r| r == "betternotes-stickies") {
            rules.push("betternotes-stickies".into());
            let count = rules.len().to_string();
            let rules_joined = rules.join(",");

            let _ = std::process::Command::new("kwriteconfig6")
                .args([
                    "--file",
                    "kwinrulesrc",
                    "--group",
                    "General",
                    "--key",
                    "rules",
                    &rules_joined,
                ])
                .status();
            let _ = std::process::Command::new("kwriteconfig6")
                .args([
                    "--file",
                    "kwinrulesrc",
                    "--group",
                    "General",
                    "--key",
                    "count",
                    &count,
                ])
                .status();
        }

        let keys = [
            ("Description", "BetterNotes Sticky Notes (Skip Taskbar)"),
            ("wmclass", "betternotes"),
            ("wmclassmatch", "1"),
            ("wmclasscomplete", "false"),
            ("types", "512"),
            ("typesrule", "2"),
            ("skiptaskbar", "true"),
            ("skiptaskbarrule", "2"),
            ("skippager", "true"),
            ("skippagerrule", "2"),
            ("skipswitcher", "true"),
            ("skipswitcherrule", "2"),
        ];

        for (k, v) in keys {
            let _ = std::process::Command::new("kwriteconfig6")
                .args([
                    "--file",
                    "kwinrulesrc",
                    "--group",
                    "betternotes-stickies",
                    "--key",
                    k,
                    v,
                ])
                .status();
        }

        let _ = std::process::Command::new("busctl")
            .args([
                "--user",
                "call",
                "org.kde.KWin",
                "/KWin",
                "org.kde.KWin",
                "reconfigure",
            ])
            .status();
    }
}

pub struct DesktopReport {
    pub display_server: DisplayServer,
    pub desktop: DesktopEnvironment,
}

impl DesktopReport {
    pub fn current() -> Self {
        Self {
            display_server: DisplayServer::detect(),
            desktop: DesktopEnvironment::detect(),
        }
    }

    pub fn format_report(&self) -> String {
        let mut out = String::new();
        out.push_str(
            "BetterNotes Platform & Compositor Diagnostics\n==============================================\n",
        );
        out.push_str(&format!(
            "Display Server:         {}\n",
            self.display_server.name()
        ));
        out.push_str(&format!(
            "Desktop Environment:    {}\n",
            self.desktop.name()
        ));
        out.push_str(&format!(
            "Window Positioning:     {}\n",
            if self.display_server.can_position_windows() {
                "Supported (Absolute X11/XCB coordinates)"
            } else {
                "Compositor-Managed (Wayland xdg-shell standard)"
            }
        ));
        out.push_str("Always-on-top:          Supported via Qt.WindowStaysOnTopHint\n");
        out.push_str(&format!(
            "System Tray:            {}\n",
            self.desktop.tray_notes()
        ));

        if let Some(rule) = self.desktop.window_rule_hint() {
            out.push_str(&format!(
                "\nTiling Compositor Rule Hint:\n-----------------------------\n{}\n",
                rule
            ));
        }

        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn note_layers_need_x11_or_kwin_on_wayland() {
        assert!(DesktopEnvironment::Gnome.supports_note_layers(DisplayServer::X11));
        assert!(DesktopEnvironment::KdePlasma.supports_note_layers(DisplayServer::Wayland));
        assert!(!DesktopEnvironment::Gnome.supports_note_layers(DisplayServer::Wayland));
        assert!(!DesktopEnvironment::Sway.supports_note_layers(DisplayServer::Wayland));
        assert!(!DesktopEnvironment::KdePlasma.supports_note_layers(DisplayServer::Unknown));
    }

    #[test]
    fn display_server_and_desktop_detection_does_not_panic() {
        let server = DisplayServer::detect();
        assert!(!server.name().is_empty());
        let desktop = DesktopEnvironment::detect();
        assert!(!desktop.name().is_empty());

        let report = DesktopReport::current();
        let formatted = report.format_report();
        assert!(formatted.contains("BetterNotes Platform & Compositor Diagnostics"));
        assert!(formatted.contains(server.name()));
        assert!(formatted.contains(desktop.name()));
    }

    #[test]
    fn tiling_compositor_hints() {
        assert!(DesktopEnvironment::Hyprland.is_tiling());
        assert!(DesktopEnvironment::Sway.is_tiling());
        assert!(!DesktopEnvironment::KdePlasma.is_tiling());
        assert!(!DesktopEnvironment::Gnome.is_tiling());

        assert!(DesktopEnvironment::Hyprland
            .window_rule_hint()
            .unwrap()
            .contains("float"));
        assert!(DesktopEnvironment::Sway
            .window_rule_hint()
            .unwrap()
            .contains("floating enable"));
        assert!(DesktopEnvironment::KdePlasma.window_rule_hint().is_none());
    }
}
