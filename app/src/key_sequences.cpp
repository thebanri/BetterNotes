#include "key_sequences.h"

#include <QKeySequence>

QString KeySequences::fromKey(int key, int modifiers) const {
    switch (key) {
    case Qt::Key_Control:
    case Qt::Key_Shift:
    case Qt::Key_Alt:
    case Qt::Key_Meta:
    case Qt::Key_AltGr:
    case Qt::Key_Super_L:
    case Qt::Key_Super_R:
    case Qt::Key_unknown:
        return {};
    default:
        break;
    }
    // Keypad is a detail of where a key sits, not part of the shortcut.
    const auto keyboardModifiers =
        Qt::KeyboardModifiers(modifiers) & ~Qt::KeypadModifier;
    return QKeySequence(QKeyCombination(keyboardModifiers, Qt::Key(key)))
        .toString(QKeySequence::PortableText);
}

QString KeySequences::display(const QString &portable) const {
    return QKeySequence::fromString(portable, QKeySequence::PortableText)
        .toString(QKeySequence::NativeText);
}
