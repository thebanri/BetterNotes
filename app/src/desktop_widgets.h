#pragma once

#include <QObject>
#include <QString>
#include <QWindow>
#include <QtQml/qqmlregistration.h>

// Sticky notes as desktop widgets: they stay on the desktop when "show
// desktop" hides the other windows, stay out of the taskbar and window
// switcher, and keep the exact place the user gave them.
//
// Wayland: each note is a layer-shell surface (zwlr_layer_shell_v1, offered
// by KDE Plasma, Hyprland, Sway and other wlroots compositors) on the bottom
// layer, or the top layer while pinned. Its scope is "dock", which KWin
// treats as a panel and so leaves out of "show desktop". The compositor does
// not move layer surfaces, so the app moves and resizes them itself.
// X11: notes get the desktop window type, or the dock type while pinned;
// window managers keep both on screen when showing the desktop.
// GNOME on Wayland has neither: there notes stay ordinary windows.
class DesktopWidgets : public QObject {
    Q_OBJECT
    QML_ELEMENT
  public:
    explicit DesktopWidgets(QObject *parent = nullptr) : QObject(parent) {}

    // "layer-shell", "x11", or "" when this session cannot host widgets.
    Q_INVOKABLE QString mode() const;
    // Makes a window a widget at a global position (x, y). Call before the
    // window is first shown. Returns false when it stays a normal window.
    Q_INVOKABLE bool attach(QWindow *window, bool above, int x, int y);
    // Moves a widget to a global position. On Wayland a shown widget stays
    // on its screen while it moves; call settle() when a drag ends.
    Q_INVOKABLE void move(QWindow *window, int x, int y);
    // Moves a widget, onto the screen holding (x, y) if that is another one.
    Q_INVOKABLE void settle(QWindow *window, int x, int y);
    // Puts a widget above other windows (pinned) or below them.
    Q_INVOKABLE void setAbove(QWindow *window, bool above);
};
