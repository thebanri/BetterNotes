use cxx_qt_lib::{QQmlApplicationEngine, QUrl};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

pub const MAIN_QML: &str = "qrc:/betternotes/windows/Main.qml";

// Resource URLs load synchronously. Do not use this helper for remote QML URLs.
pub fn load_engine(url: &str) -> Result<cxx::UniquePtr<QQmlApplicationEngine>, &'static str> {
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
