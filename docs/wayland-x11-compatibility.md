# Wayland / X11 Compositor Compatibility Guide

BetterNotes is built Linux-first with equal support for **Wayland** and **X11** display servers across major desktop environments and tiling window managers.

---

## 1. Supported Environments Matrix

| Environment | Primary Display Server | Window Placement | Always-on-top | System Tray | Global Shortcuts |
|---|---|---|---|---|---|
| **KDE Plasma** | Wayland / X11 | Client on X11; Compositor on Wayland | Native (`Qt.WindowStaysOnTopHint`) | Native Freedesktop SNI | Portal (`xdg-desktop-portal-kde`) / X11 |
| **GNOME** | Wayland / X11 | Client on X11; Compositor on Wayland | StaysOnTop hint supported | Requires `AppIndicator` shell extension | Portal (`xdg-desktop-portal-gnome`) / X11 |
| **XFCE** | X11 (Wayland experimental) | Native X11 absolute positioning | Native EWMH | Native XFCE tray / SNI | Native X11 key grab |
| **Cinnamon** | X11 / Wayland | Native X11; Compositor on Wayland | Native EWMH / Wayland hint | Native panel tray | Native X11 / Cinnamon keybindings |
| **MATE** | X11 | Native X11 absolute positioning | Native EWMH | Native notification area | Native X11 key grab |
| **Budgie** | X11 (Wayland in dev) | Native X11 absolute positioning | Native EWMH | Native panel tray | Native X11 key grab |
| **Hyprland** | Wayland only | Managed by compositor (Window rules for float) | Supported in floating mode (`pin` or stays-on-top) | Requires Waybar with `tray` module | Compositor `bind` or portal |
| **Sway** | Wayland only | Managed by compositor (Criteria for float) | Supported in floating mode | Requires Swaybar / Waybar with `tray` | Compositor `bindsym` or portal |

---

## 2. Wayland Rules & Unavoidable Limitations

Wayland's security architecture differs fundamentally from X11:

### A. Window Placement
- **Limitation:** In the `xdg-shell` protocol, clients **cannot** dictate arbitrary global `(x, y)` screen coordinates. Only the compositor knows the global workspace and display geometry.
- **Why it exists:** Security and multi-output sandboxing prevent rogue windows from positioning themselves invisibly or covering other applications (clickjacking prevention).
- **Graceful Behavior:** BetterNotes automatically detects when running under Wayland (`can_position_windows` returns `false`). Instead of asserting invalid screen positions, window size and display monitor are requested, allowing the compositor to position the note according to user workspace policies.

### B. Tiling Compositors (Hyprland & Sway)
In dynamic tiling compositors, new windows tile by default. Sticky notes are intended to float.
- **Hyprland:** Add the following rule to `~/.config/hypr/hyprland.conf`:
  ```ini
  windowrule = float, ^(betternotes)$
  windowrule = size 380 360, ^(betternotes)$
  ```
- **Sway:** Add the following criteria to `~/.config/sway/config`:
  ```ini
  for_window [app_id="betternotes"] floating enable
  ```

### C. Always-on-top Behavior
- BetterNotes exposes the `alwaysOnTop` toggle on each sticky note window via `Qt.WindowStaysOnTopHint`.
- On KDE Plasma, Sway, and Hyprland, `Qt.WindowStaysOnTopHint` informs the compositor to keep the note above normal windows.
- On GNOME Wayland, standard top-level windows may be restricted by Mutter window management unless enabled by window manager action or extensions.

### D. Window Activation
- **Limitation:** Wayland compositors employ focus-stealing prevention. Calling `requestActivate()` without an `xdg-activation-v1` token might demand attention (flashing taskbar item) rather than immediately grabbing focus.
- **Handling:** BetterNotes uses `requestActivate()` which Qt Wayland maps to the `xdg-activation` protocol when a token is provided.

### E. System Tray
- BetterNotes implements `Platform.SystemTrayIcon` with graceful fallback (`systemTray.available`).
- If a tray is not present (e.g. stock GNOME without `gnome-shell-extension-appindicator`), BetterNotes remains fully usable through its library window and standard shortcuts.

### F. Global Shortcuts
- On X11, global hotkeys can be grabbed directly.
- On Wayland, the Freedesktop `GlobalShortcuts` portal (`org.freedesktop.portal.GlobalShortcuts`) is used where available. Alternatively, users can bind native compositor keys to launch `betternotes --quick-capture`.

---

## 3. Command Line Diagnostics

To inspect your current desktop environment, display server, and active platform integration capabilities:

```sh
betternotes --diagnostics
```
Output includes display server type, desktop classification, window positioning capability, system tray status notes, and copy-pasteable window rules for Hyprland and Sway.
