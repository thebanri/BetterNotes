use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("BetterNotes.App"))
        .file("src/bridge.rs")
        .file("src/notes_bridge.rs")
        .cpp_file("src/platform_helper.cpp")
        .cpp_file("src/text_formatter.h")
        .cpp_file("src/text_formatter.cpp")
        .cpp_file("src/window_placement.h")
        .cpp_file("src/window_placement.cpp")
        .qrc("../qml/qml.qrc")
        .qt_module("Gui")
        .qt_module("Quick")
        .qt_module("Widgets")
        .qt_module("DBus")
        .build();

    // cxx-qt passes -lQt6DBus ahead of the static archive holding our C++,
    // and window_placement.cpp is the only code that uses Qt D-Bus. With
    // --as-needed, GNU ld (Fedora, Debian) drops the library before it sees
    // the reference and then fails with "DSO missing from command line".
    // Naming it again after the archives keeps it; lld is order-insensitive.
    println!("cargo:rustc-link-arg-bins=-lQt6DBus");
}
