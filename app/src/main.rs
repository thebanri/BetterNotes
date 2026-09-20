mod bridge;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

const MAIN_QML: &str = "qrc:/betternotes/windows/Main.qml";

// Resource URLs load synchronously. Do not use this helper for remote QML URLs.
fn load_engine(url: &str) -> Result<cxx::UniquePtr<QQmlApplicationEngine>, &'static str> {
    let mut engine = QQmlApplicationEngine::new();
    // CXX-Qt signal closures require Send, even for this synchronous GUI load.
    let loaded = Arc::new(AtomicBool::new(false));
    let created = Arc::clone(&loaded);
    let mut pinned = engine.as_mut().ok_or("could not create the QML engine")?;
    pinned
        .as_mut()
        .on_object_created(move |_, object, _| {
            created.store(!object.is_null(), Ordering::Relaxed);
        })
        .release();
    pinned.load(&QUrl::from(url));
    if !loaded.load(Ordering::Relaxed) {
        return Err("could not load the application window; see Qt diagnostics above");
    }
    Ok(engine)
}

fn run() -> Result<i32, &'static str> {
    let mut app = QGuiApplication::new();
    let mut app = app.as_mut().ok_or("could not create the Qt application")?;
    app.as_mut()
        .set_application_name(&betternotes_core::APPLICATION_NAME.into());
    app.as_mut()
        .set_application_version(&betternotes_core::APPLICATION_VERSION.into());
    // Keep the engine alive until the event loop ends and drop it before Qt.
    let _engine = load_engine(MAIN_QML)?;
    eprintln!("BetterNotes: application window loaded");
    Ok(app.exec())
}

fn main() -> std::process::ExitCode {
    match run() {
        Ok(0) => std::process::ExitCode::SUCCESS,
        Ok(code) => {
            eprintln!("BetterNotes: Qt event loop exited with code {code}");
            std::process::ExitCode::FAILURE
        }
        Err(error) => {
            eprintln!("BetterNotes: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // One Qt application per process. This test is headless and does not need a
    // running compositor; desktop interaction requires separate validation.
    #[test]
    fn embedded_window_loads_and_missing_resource_returns_error() {
        std::env::set_var("QT_QPA_PLATFORM", "offscreen");
        std::env::set_var("QT_QUICK_BACKEND", "software");
        let _app = QGuiApplication::new();
        let engine = load_engine(MAIN_QML).expect("embedded QML window must load");
        drop(engine);
        assert!(load_engine("qrc:/betternotes/missing.qml").is_err());
    }
}
