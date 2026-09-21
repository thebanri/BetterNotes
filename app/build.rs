use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("BetterNotes.App"))
        .file("src/bridge.rs")
        .file("src/notes_bridge.rs")
        .cpp_file("src/platform_helper.cpp")
        .cpp_file("src/text_formatter.h")
        .cpp_file("src/text_formatter.cpp")
        .cpp_file("src/image_animator.h")
        .cpp_file("src/image_animator.cpp")
        .cpp_file("src/window_placement.h")
        .cpp_file("src/window_placement.cpp")
        .qrc("../qml/qml.qrc")
        .qt_module("Gui")
        .qt_module("Quick")
        .qt_module("Widgets")
        .qt_module("DBus")
        .build();

    // cxx-qt passes the Qt libraries ahead of the static archive holding our
    // own C++ (QApplication in platform_helper.cpp, QQuickTextDocument in
    // text_formatter.cpp, Qt D-Bus in window_placement.cpp). With
    // --as-needed, GNU ld (Fedora) drops each one before it sees the
    // reference and fails with "DSO missing from command line". Naming them
    // again after the archives keeps them; lld (Arch) is order-insensitive.
    // Every target needs it: the app and the QML integration test.
    for module in ["Widgets", "Quick", "DBus", "Qml", "Gui", "Core"] {
        println!("cargo:rustc-link-arg=-lQt6{module}");
    }
}
