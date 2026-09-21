#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

// Turns a key press into a shortcut the way Qt writes it ("Ctrl+Shift+B"),
// for recording shortcuts in the settings.
class KeySequences : public QObject {
    Q_OBJECT
    QML_ELEMENT
  public:
    explicit KeySequences(QObject *parent = nullptr) : QObject(parent) {}

    // The portable text for a key with modifiers, or "" while only modifier
    // keys are held.
    Q_INVOKABLE QString fromKey(int key, int modifiers) const;
    // A portable shortcut as this desktop shows it ("Strg+B" in German).
    Q_INVOKABLE QString display(const QString &portable) const;
};
