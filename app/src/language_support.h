#pragma once

#include <QObject>
#include <QString>
#include <QTranslator>
#include <QtQml/qqmlregistration.h>
#include <memory>

// Switches the interface language: loads the app's translation (embedded as
// qrc:/betternotes/windows/i18n/qml_<lang>.qm) and Qt's own (standard dialog
// buttons, file dialogs), then has the QML engine retranslate every window.
class LanguageSupport : public QObject {
    Q_OBJECT
    QML_ELEMENT
  public:
    explicit LanguageSupport(QObject *parent = nullptr) : QObject(parent) {}
    ~LanguageSupport() override;

    // The language to use for "system": "tr" when the desktop is Turkish,
    // otherwise "en".
    Q_INVOKABLE QString systemLanguage() const;
    // Installs Qt's translations for a language code; English needs none.
    // A missing translation file is not an error: Qt's texts stay English.
    Q_INVOKABLE void apply(const QString &language);

  private:
    void remove();
    std::unique_ptr<QTranslator> m_app;
    std::unique_ptr<QTranslator> m_base;
    std::unique_ptr<QTranslator> m_declarative;
};
