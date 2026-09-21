#include "language_support.h"

#include <QCoreApplication>
#include <QLibraryInfo>
#include <QLocale>
#include <QQmlEngine>

LanguageSupport::~LanguageSupport() { remove(); }

QString LanguageSupport::systemLanguage() const {
    return QLocale::system().language() == QLocale::Turkish ? QStringLiteral("tr")
                                                            : QStringLiteral("en");
}

void LanguageSupport::remove() {
    if (m_app)
        QCoreApplication::removeTranslator(m_app.get());
    if (m_base)
        QCoreApplication::removeTranslator(m_base.get());
    if (m_declarative)
        QCoreApplication::removeTranslator(m_declarative.get());
    m_app.reset();
    m_base.reset();
    m_declarative.reset();
}

void LanguageSupport::apply(const QString &language) {
    remove();
    auto load = [&](const QString &name, const QString &path) -> std::unique_ptr<QTranslator> {
        auto translator = std::make_unique<QTranslator>();
        if (!translator->load(name, path))
            return nullptr;
        QCoreApplication::installTranslator(translator.get());
        return translator;
    };
    // English has a translation too: it holds the plural forms.
    m_app = load(QStringLiteral("qml_%1").arg(language),
                 QStringLiteral(":/betternotes/windows/i18n"));
    if (language != QLatin1String("en")) {
        const QString qt = QLibraryInfo::path(QLibraryInfo::TranslationsPath);
        m_base = load(QStringLiteral("qtbase_%1").arg(language), qt);
        m_declarative = load(QStringLiteral("qtdeclarative_%1").arg(language), qt);
    }
    if (auto *engine = qmlEngine(this))
        engine->retranslate();
}
