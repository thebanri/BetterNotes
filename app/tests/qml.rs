// Run Qt on the process main thread, outside Rust libtest worker threads.
#[path = "../src/bridge.rs"]
mod bridge;
#[path = "../src/engine.rs"]
mod engine;
#[path = "../src/notes_bridge.rs"]
mod notes_bridge;
#[path = "../src/platform.rs"]
mod platform;

use cxx_qt::casting::Upcast;
use cxx_qt_lib::{QByteArray, QGuiApplication, QQmlApplicationEngine, QQmlEngine, QUrl};
use engine::{load_engine, MAIN_QML};
use std::{
    pin::Pin,
    sync::{
        atomic::{AtomicBool, AtomicI32, Ordering},
        Arc,
    },
};

// One Qt application per process. This test is headless and does not need a
// running compositor; desktop interaction requires separate validation.
fn main() {
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
    let loaded = Arc::new(AtomicBool::new(false));
    let created = Arc::clone(&loaded);
    engine
        .pin_mut()
        .on_object_created(move |_, object, _| {
            created.store(!object.is_null(), Ordering::Relaxed);
        })
        .release();
    let result = Arc::new(AtomicI32::new(-1));
    let exit_result = Arc::clone(&result);
    let qml_engine: Pin<&mut QQmlEngine> = engine.pin_mut().upcast_pin();
    qml_engine
        .on_exit(move |_, code| exit_result.store(code, Ordering::Relaxed))
        .release();
    engine.pin_mut().load_data(
        &QByteArray::from(include_str!("notes_flow.qml")),
        &QUrl::from("qrc:/tests/notes_flow.qml"),
    );
    assert!(
        loaded.load(Ordering::Relaxed),
        "QML test fixture did not load"
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
    assert_eq!(notes.len(), 2);
    let note = store.get(notes[1].id).unwrap();
    assert_eq!(note.title, "Other process");
    assert_eq!(
        note.content,
        "Plain <b>text</b>\nİstanbul 🦀\nSaved on quit"
    );
    let state = store.window_state(note.id).unwrap();
    assert!(state.open && state.collapsed);
    assert_eq!((state.width, state.height), (420, 320));
    assert_eq!(store.open_window_ids().unwrap(), [note.id]);
    let second = store.get(notes[0].id).unwrap();
    assert_eq!(second.content, "Independent draft\nSaved on close");
    assert!(!store.window_state(second.id).unwrap().open);
    println!(
        "Qt/QML integration passed: multiple windows, autosave, geometry, recovery and failed quit"
    );
}
