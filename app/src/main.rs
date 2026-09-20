mod bridge;
mod notes_bridge;

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
    use cxx_qt::casting::Upcast;
    use cxx_qt_lib::{QByteArray, QQmlEngine};
    use std::{pin::Pin, sync::atomic::AtomicI32};

    // One Qt application per process. This test is headless and does not need a
    // running compositor; desktop interaction requires separate validation.
    #[test]
    fn qml_notes_autosave_switch_delete_close_and_resource_errors() {
        std::env::set_var("QT_QPA_PLATFORM", "offscreen");
        std::env::set_var("QT_QUICK_BACKEND", "software");
        std::env::set_var("QT_FORCE_STDERR_LOGGING", "1");
        let directory = tempfile::tempdir().unwrap();
        std::env::set_var("XDG_DATA_HOME", directory.path());
        let mut app = QGuiApplication::new();
        let engine = load_engine(MAIN_QML).expect("embedded QML window must load");
        drop(engine);
        assert!(load_engine("qrc:/betternotes/missing.qml").is_err());

        let mut engine = QQmlApplicationEngine::new();
        let result = Arc::new(AtomicI32::new(-1));
        let exit_result = Arc::clone(&result);
        let qml_engine: Pin<&mut QQmlEngine> = engine.pin_mut().upcast_pin();
        qml_engine
            .on_exit(move |_, code| exit_result.store(code, Ordering::Relaxed))
            .release();
        engine.pin_mut().load_data(
            &QByteArray::from(include_str!("../tests/notes_flow.qml")),
            &QUrl::from("qrc:/tests/notes_flow.qml"),
        );
        assert_eq!(app.pin_mut().exec(), 0);
        assert_eq!(
            result.load(Ordering::Relaxed),
            0,
            "QML integration assertions failed"
        );
        drop(engine);
        let store =
            betternotes_core::NoteStore::open(&directory.path().join("betternotes/notes.sqlite3"))
                .unwrap();
        let notes = store.list().unwrap();
        assert_eq!(notes.len(), 1);
        let note = store.get(notes[0].id).unwrap();
        assert_eq!(note.title, "Autosaved title");
        assert_eq!(
            note.content,
            "Plain <b>text</b>\nİstanbul 🦀\nSaved on close"
        );
    }
}
