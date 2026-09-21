#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

// Remembers where sticky notes sit on a Wayland desktop.
//
// Wayland lets no client read or set its own window position, so the app
// cannot save or restore note positions itself. On KDE Plasma the desktop
// integration's KWin script can: it asks this object where a note belongs when
// the note's window appears, and reports where the user left it after a move.
// The two talk over the session bus; a note identifies itself to the script by
// an invisible key in its window caption (see StickyNote.qml).
class WindowPlacement : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_CLASSINFO("D-Bus Interface", "org.betternotes.BetterNotes.Placement")
    Q_PROPERTY(bool available READ available CONSTANT)

  public:
    explicit WindowPlacement(QObject *parent = nullptr);
    ~WindowPlacement() override;

    // False when the session bus or the service name is unavailable, e.g. a
    // second instance or a desktop without a session bus.
    bool available() const { return m_available; }

    // Called by a note before its window appears: its saved position, if any.
    Q_INVOKABLE void track(const QString &noteId, bool positioned, int x, int y);
    Q_INVOKABLE void forget(const QString &noteId);

  public Q_SLOTS:
    // D-Bus: the saved position of an open note as "x,y", or "" if unknown.
    Q_SCRIPTABLE QString Placement(const QString &noteId) const;
    // D-Bus: where the window manager placed or the user moved an open note.
    Q_SCRIPTABLE void Moved(const QString &noteId, int x, int y);

  Q_SIGNALS:
    void moved(const QString &noteId, int x, int y);

  private:
    struct Entry {
        bool positioned = false;
        int x = 0;
        int y = 0;
    };
    QHash<QString, Entry> m_notes;
    bool m_available = false;
};
