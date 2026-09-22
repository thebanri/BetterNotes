#include "desktop_widgets.h"

#include <QGuiApplication>
#include <QMargins>
#include <QQuickWindow>
#include <QScreen>
#include <QWindow>

#ifdef BETTERNOTES_LAYER_SHELL
#include <LayerShellQt/window.h>
#include <cstring>
#include <wayland-client.h>

#include "protocols/relative-pointer-unstable-v1-client.h"
extern "C" {
// Generated from protocols/relative-pointer-unstable-v1.xml by
// wayland-scanner private-code.
#include "protocols/relative-pointer-unstable-v1-protocol.c"
}
#endif

#ifdef BETTERNOTES_XCB_WINDOW_TYPE
#include <QtGui/qpa/qplatformwindow_p.h>
#endif

namespace {
[[maybe_unused]] bool isPlatform(const char *name) {
    return QGuiApplication::platformName() == QLatin1String(name);
}

// The screen holding a global point, or the primary one when none does
// (for example a monitor that has since been unplugged).
[[maybe_unused]] QScreen *screenAt(int x, int y) {
    if (auto *screen = QGuiApplication::screenAt(QPoint(x, y)))
        return screen;
    return QGuiApplication::primaryScreen();
}

#ifdef BETTERNOTES_LAYER_SHELL
struct Globals {
    bool layerShell = false;
    // Relative pointer motion, on Qt's default event queue so its events
    // arrive on the GUI thread; null when the compositor lacks it.
    zwp_relative_pointer_manager_v1 *relativePointers = nullptr;
};

// What the compositor offers. Asked on a private event queue, so Qt's own
// Wayland event handling is not disturbed.
const Globals &globals() {
    static const Globals found = [] {
        Globals result;
        auto *wayland = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
        wl_display *display = wayland ? wayland->display() : nullptr;
        if (!display)
            return result;
        wl_event_queue *queue = wl_display_create_queue(display);
        auto *wrapped = static_cast<wl_display *>(wl_proxy_create_wrapper(display));
        wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(wrapped), queue);
        wl_registry *registry = wl_display_get_registry(wrapped);
        static const wl_registry_listener listener = {
            [](void *data, wl_registry *registry, uint32_t name, const char *interface,
               uint32_t) {
                auto *result = static_cast<Globals *>(data);
                if (std::strcmp(interface, "zwlr_layer_shell_v1") == 0)
                    result->layerShell = true;
                else if (std::strcmp(interface, zwp_relative_pointer_manager_v1_interface.name) == 0)
                    result->relativePointers = static_cast<zwp_relative_pointer_manager_v1 *>(
                        wl_registry_bind(registry, name, &zwp_relative_pointer_manager_v1_interface, 1));
            },
            [](void *, wl_registry *, uint32_t) {},
        };
        wl_registry_add_listener(registry, &listener, &result);
        wl_display_roundtrip_queue(display, queue);
        if (result.relativePointers)
            wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(result.relativePointers), nullptr);
        wl_registry_destroy(registry);
        wl_proxy_wrapper_destroy(wrapped);
        wl_event_queue_destroy(queue);
        return result;
    }();
    return found;
}

// The one widget being dragged or resized, which relative motion goes to.
DesktopWidgets *tracker = nullptr;

// Relative motion of Qt's pointer: how far the pointer moved, whatever the
// surface under it did in the meantime.
void watchRelativeMotion() {
    static zwp_relative_pointer_v1 *relative = nullptr;
    static wl_pointer *watched = nullptr;
    auto *wayland = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>();
    wl_pointer *pointer = wayland ? wayland->pointer() : nullptr;
    if (!globals().relativePointers || !pointer || pointer == watched)
        return;
    if (relative)
        zwp_relative_pointer_v1_destroy(relative);
    watched = pointer;
    relative = zwp_relative_pointer_manager_v1_get_relative_pointer(globals().relativePointers, pointer);
    static const zwp_relative_pointer_v1_listener listener = {
        [](void *, zwp_relative_pointer_v1 *, uint32_t, uint32_t, wl_fixed_t dx, wl_fixed_t dy,
           wl_fixed_t, wl_fixed_t) {
            if (tracker)
                tracker->addPointerMotion(wl_fixed_to_double(dx), wl_fixed_to_double(dy));
        },
    };
    zwp_relative_pointer_v1_add_listener(relative, &listener, nullptr);
}

// A layer surface lives on one output, the QWindow's screen when it is shown
// (LayerShellQt's default); moving a shown one to another output takes a new
// surface, which settle() makes.
void placeLayer(LayerShellQt::Window *layer, QWindow *window, int x, int y) {
    QScreen *screen = window->isVisible() && window->screen() ? window->screen() : screenAt(x, y);
    window->setScreen(screen);
    const QRect area = screen->geometry();
    // Margins from the output's top-left corner. An exclusive zone of -1 puts
    // the surface there even where a panel reserves space.
    layer->setMargins(QMargins(x - area.x(), y - area.y(), 0, 0));
}

// Layer-shell changes take effect with the surface's next commit; draw a
// frame so there is one.
void commit(QWindow *window) {
    if (auto *quick = qobject_cast<QQuickWindow *>(window))
        quick->update();
    else
        window->requestUpdate();
}
#endif

#ifdef BETTERNOTES_XCB_WINDOW_TYPE
void setXcbType(QWindow *window, bool above) {
    window->create();
    if (auto *xcb = window->nativeInterface<QNativeInterface::Private::QXcbWindow>())
        xcb->setWindowType(above ? QNativeInterface::Private::QXcbWindow::Dock
                                 : QNativeInterface::Private::QXcbWindow::Desktop);
}
#endif
} // namespace

QString DesktopWidgets::mode() const {
#ifdef BETTERNOTES_LAYER_SHELL
    static const bool layerShell = isPlatform("wayland") && globals().layerShell;
    if (layerShell)
        return QStringLiteral("layer-shell");
#endif
#ifdef BETTERNOTES_XCB_WINDOW_TYPE
    if (isPlatform("xcb"))
        return QStringLiteral("x11");
#endif
    return {};
}

bool DesktopWidgets::attach(QWindow *window, bool above, int x, int y) {
    if (!window)
        return false;
    const QString current = mode();
#ifdef BETTERNOTES_LAYER_SHELL
    if (current == QLatin1String("layer-shell")) {
        auto *layer = LayerShellQt::Window::get(window);
        if (!layer)
            return false;
        layer->setScope(QStringLiteral("dock"));
        layer->setLayer(above ? LayerShellQt::Window::LayerTop : LayerShellQt::Window::LayerBottom);
        layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop |
                                                        LayerShellQt::Window::AnchorLeft));
        layer->setExclusiveZone(-1);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        placeLayer(layer, window, x, y);
        layer->setDesiredSize(window->size());
        if (!window->property("_betternotes_layer_connected").toBool()) {
            window->setProperty("_betternotes_layer_connected", true);
            QObject::connect(window, &QWindow::widthChanged, layer, [layer, window](int) {
                layer->setDesiredSize(window->size());
                commit(window);
            });
            QObject::connect(window, &QWindow::heightChanged, layer, [layer, window](int) {
                layer->setDesiredSize(window->size());
                commit(window);
            });
        }
        return true;
    }
#endif
#ifdef BETTERNOTES_XCB_WINDOW_TYPE
    if (current == QLatin1String("x11")) {
        setXcbType(window, above);
        window->setPosition(x, y);
        return true;
    }
#endif
    Q_UNUSED(above)
    Q_UNUSED(x)
    Q_UNUSED(y)
    Q_UNUSED(current)
    return false;
}

void DesktopWidgets::move(QWindow *window, int x, int y) {
    if (!window)
        return;
#ifdef BETTERNOTES_LAYER_SHELL
    if (mode() == QLatin1String("layer-shell")) {
        if (auto *layer = LayerShellQt::Window::get(window)) {
            placeLayer(layer, window, x, y);
            commit(window);
        }
        return;
    }
#endif
    window->setPosition(x, y);
}

void DesktopWidgets::settle(QWindow *window, int x, int y) {
    if (!window)
        return;
#ifdef BETTERNOTES_LAYER_SHELL
    if (mode() == QLatin1String("layer-shell") && window->isVisible() &&
        screenAt(x, y) != window->screen()) {
        window->hide();
        if (auto *layer = LayerShellQt::Window::get(window))
            placeLayer(layer, window, x, y);
        window->show();
        return;
    }
#endif
    move(window, x, y);
}

void DesktopWidgets::setAbove(QWindow *window, bool above) {
    if (!window)
        return;
#ifdef BETTERNOTES_LAYER_SHELL
    if (mode() == QLatin1String("layer-shell")) {
        if (auto *layer = LayerShellQt::Window::get(window)) {
            layer->setLayer(above ? LayerShellQt::Window::LayerTop
                                  : LayerShellQt::Window::LayerBottom);
            commit(window);
        }
        return;
    }
#endif
#ifdef BETTERNOTES_XCB_WINDOW_TYPE
    if (mode() == QLatin1String("x11")) {
        // Window managers read the type when a window is mapped.
        const bool visible = window->isVisible();
        const QPoint position = window->position();
        if (visible)
            window->hide();
        setXcbType(window, above);
        if (visible) {
            window->setPosition(position);
            window->show();
        }
    }
#endif
    Q_UNUSED(above)
}

void DesktopWidgets::resize(QWindow *window, int width, int height) {
    if (!window)
        return;
#ifdef BETTERNOTES_LAYER_SHELL
    if (mode() == QLatin1String("layer-shell")) {
        if (auto *layer = LayerShellQt::Window::get(window)) {
            layer->setDesiredSize(QSize(width, height));
            commit(window);
        }
        return;
    }
#endif
    window->resize(width, height);
}

bool DesktopWidgets::trackPointer() {
    m_pointer = QPointF();
#ifdef BETTERNOTES_LAYER_SHELL
    if (mode() == QLatin1String("layer-shell") && globals().relativePointers) {
        watchRelativeMotion();
        tracker = this;
        return true;
    }
#endif
    return false;
}

void DesktopWidgets::stopTracking() {
#ifdef BETTERNOTES_LAYER_SHELL
    if (tracker == this)
        tracker = nullptr;
#endif
}

DesktopWidgets::~DesktopWidgets() { stopTracking(); }

void DesktopWidgets::addPointerMotion(double dx, double dy) {
    m_pointer += QPointF(dx, dy);
    Q_EMIT pointerMoved(m_pointer.x(), m_pointer.y());
}
