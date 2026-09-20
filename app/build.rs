use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("BetterNotes.App"))
        .file("src/bridge.rs")
        .file("src/notes_bridge.rs")
        .qrc("../qml/qml.qrc")
        .qt_module("Quick")
        .build();
}
