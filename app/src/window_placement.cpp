#include "window_placement.h"

#include <QDBusConnection>
#include <cstdlib>

namespace {
const auto kService = QStringLiteral("org.betternotes.BetterNotes");
const auto kPath = QStringLiteral("/Placement");
// Far beyond any real desktop, but keeps nonsense out of the database.
constexpr int kCoordinateLimit = 100000;

bool isNoteId(const QString &id) {
    if (id.isEmpty() || id.size() > 18)
        return false;
    for (const QChar c : id)
        if (!c.isDigit())
            return false;
    return true;
}
} // namespace

WindowPlacement::WindowPlacement(QObject *parent) : QObject(parent) {
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || !bus.registerService(kService))
        return;
    m_available =
        bus.registerObject(kPath, this, QDBusConnection::ExportScriptableSlots);
    if (!m_available)
        bus.unregisterService(kService);
}

WindowPlacement::~WindowPlacement() {
    if (!m_available)
        return;
    auto bus = QDBusConnection::sessionBus();
    bus.unregisterObject(kPath);
    bus.unregisterService(kService);
}

void WindowPlacement::track(const QString &noteId, bool positioned, int x,
                            int y) {
    if (!isNoteId(noteId))
        return;
    m_notes.insert(noteId, {positioned, x, y});
}

void WindowPlacement::forget(const QString &noteId) { m_notes.remove(noteId); }

QString WindowPlacement::Placement(const QString &noteId) const {
    const auto entry = m_notes.constFind(noteId);
    if (entry == m_notes.constEnd() || !entry->positioned)
        return {};
    return QStringLiteral("%1,%2").arg(entry->x).arg(entry->y);
}

void WindowPlacement::Moved(const QString &noteId, int x, int y) {
    // Any program on the session bus can call this: accept only open notes
    // and plausible coordinates.
    auto entry = m_notes.find(noteId);
    if (entry == m_notes.end() || std::abs(x) > kCoordinateLimit ||
        std::abs(y) > kCoordinateLimit)
        return;
    if (entry->positioned && entry->x == x && entry->y == y)
        return;
    *entry = {true, x, y};
    emit moved(noteId, x, y);
}
