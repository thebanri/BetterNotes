#include "desktop_widgets.h"

#include <QGuiApplication>
#include <QMargins>
#include <QMouseEvent>
#include <QPointer>
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

// The screen for a widget at (x, y): the one under the middle of its header,
// as StickyNote.moveWidgetTo() decides it.
[[maybe_unused]] QScreen *widgetScreen(QWindow *window, int x, int y) {
    return screenAt(x + window->width() / 2, y + 20);
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
    QScreen *screen =
        window->isVisible() && window->screen() ? window->screen() : widgetScreen(window, x, y);
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

// Widgets in the order their surfaces were mapped, which is how the
// compositor stacks them within a layer: the last one is on top.
QList<QPointer<QWindow>> &mapOrder() {
    static QList<QPointer<QWindow>> order;
    return order;
}

// Whether a widget mapped after this one, on the same screen and layer,
// overlaps it.
bool covered(QWindow *window) {
    const auto *layer = LayerShellQt::Window::get(window);
    const auto bounds = [](QWindow *widget) {
        const QMargins margins = LayerShellQt::Window::get(widget)->margins();
        return QRect(QPoint(margins.left(), margins.top()), widget->size());
    };
    const QRect area = bounds(window);
    const auto &order = mapOrder();
    for (qsizetype i = order.indexOf(window) + 1; i < order.size(); ++i) {
        QWindow *other = order.at(i);
        if (other && other->isVisible() && other->screen() == window->screen() &&
            LayerShellQt::Window::get(other)->layer() == layer->layer() &&
            bounds(other).intersects(area))
            return true;
    }
    return false;
}

// Brings a clicked widget to the front of its layer. Layer-shell has no
// request for that and KWin does not raise a layer surface when it is
// clicked, so the note being edited could stay under another one. A surface
// mapped anew goes on top, so a covered widget is remapped once the click is
// over: replacing the surface mid-press would cancel the press. Whether it is
// covered is decided after the click is handled, as the click may expand it.
class Restacker : public QObject {
  public:
    explicit Restacker(QWindow *window) : QObject(window), m_window(window) {
        setObjectName(QStringLiteral("restacker"));
        window->installEventFilter(this);
    }

    bool eventFilter(QObject *, QEvent *event) override {
        if (event->type() == QEvent::Show) {
            mapOrder().removeIf([this](const QPointer<QWindow> &widget) {
                return !widget || widget == m_window;
            });
            mapOrder().append(m_window);
        } else if (event->type() == QEvent::MouseButtonRelease) {
            auto *release = static_cast<QMouseEvent *>(event);
            if (release->button() != Qt::LeftButton || release->buttons() != Qt::NoButton)
                return false;
            // Remap only once the click's frame is on screen: a note expanded
            // by the click and remapped before drawing its new size shows its
            // collapsed frame stretched for a moment.
            if (auto *quick = qobject_cast<QQuickWindow *>(m_window)) {
                connect(quick, &QQuickWindow::frameSwapped, this, &Restacker::remap,
                        Qt::ConnectionType(Qt::QueuedConnection | Qt::SingleShotConnection));
                quick->update();
            } else {
                QMetaObject::invokeMethod(this, &Restacker::remap, Qt::QueuedConnection);
            }
        }
        return false;
    }

    void remap() {
        if (!m_window->isVisible() || !covered(m_window))
            return;
        // Margins and screen stay, so the widget comes back in place; the
        // new surface asks for focus as it is shown (activateOnShow).
        m_window->hide();
        m_window->show();
    }

  private:
    QWindow *m_window;
};
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
        if (!window->findChild<QObject *>(QStringLiteral("restacker"), Qt::FindDirectChildrenOnly))
            new Restacker(window);
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
        widgetScreen(window, x, y) != window->screen()) {
        window->hide();
        if (auto *layer = LayerShellQt::Window::get(window))
            placeLayer(layer, window, x, y);
        window->show();
        return;
    }
#endif
    move(window, x, y);
}

void DesktopWidgets::raise(QWindow *window) {
    if (!window)
        return;
#ifdef BETTERNOTES_LAYER_SHELL
    if (auto *restacker =
            window->findChild<QObject *>(QStringLiteral("restacker"), Qt::FindDirectChildrenOnly))
        static_cast<Restacker *>(restacker)->remap();
    return;
#endif
    window->raise();
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

bool DesktopWidgets::trackPointer() {
    m_pointer = QPointF();
#ifdef BETTERNOTES_LAYER_SHELL
    if (mode() == QLatin1String("layer-shell") && globals().relativePointers) {
        watchRelativeMotion();
        tracker = this;
        qApp->installEventFilter(this);
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
    qApp->removeEventFilter(this);
}

// Watches the whole app, as the release may come to a surface other than the
// one pressed: settle() replaces a surface mid-drag.
bool DesktopWidgets::eventFilter(QObject *watched, QEvent *event) {
    switch (event->type()) {
    case QEvent::MouseButtonRelease:
        if (!(static_cast<QMouseEvent *>(event)->buttons() & Qt::LeftButton))
            Q_EMIT pointerReleased();
        break;
    // The drag follows relative motion, not pointer positions. Without the
    // pressed surface, those would hover whatever the pointer crosses: the
    // note's own buttons or another window of the app.
    case QEvent::MouseMove:
    case QEvent::Enter:
        if (watched->isWindowType())
            return true;
        break;
    default:
        break;
    }
    return QObject::eventFilter(watched, event);
}

DesktopWidgets::~DesktopWidgets() { stopTracking(); }

void DesktopWidgets::addPointerMotion(double dx, double dy) {
    m_pointer += QPointF(dx, dy);
    Q_EMIT pointerMoved(m_pointer.x(), m_pointer.y());
}
