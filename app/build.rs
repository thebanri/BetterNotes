use cxx_qt_build::{CxxQtBuilder, QmlModule};
use std::path::{Path, PathBuf};
use std::process::Command;

/// A value from the qmake that cxx-qt builds against (QMAKE, else qmake6).
fn qmake_query(name: &str) -> Option<String> {
    let qmake = std::env::var("QMAKE").unwrap_or_else(|_| "qmake6".into());
    let output = Command::new(qmake).args(["-query", name]).output().ok()?;
    let value = String::from_utf8(output.stdout).ok()?.trim().to_string();
    (output.status.success() && !value.is_empty()).then_some(value)
}

/// Optional pieces for desktop widgets (src/desktop_widgets.h), found next
/// to the Qt being used. Without them the app builds and notes stay normal
/// windows. BETTERNOTES_NO_DESKTOP_WIDGETS=1 leaves them out on purpose.
struct DesktopWidgetSupport {
    /// LayerShellQt's include and library directories (Wayland).
    layer_shell: Option<(PathBuf, PathBuf)>,
    /// Qt's private QtGui headers, for the X11 window type.
    private_headers: Vec<PathBuf>,
}

fn desktop_widget_support() -> DesktopWidgetSupport {
    println!("cargo:rerun-if-env-changed=BETTERNOTES_NO_DESKTOP_WIDGETS");
    println!("cargo:rerun-if-env-changed=QMAKE");
    println!("cargo:rerun-if-env-changed=BETTERNOTES_LAYER_SHELL_PREFIX");
    let none = DesktopWidgetSupport {
        layer_shell: None,
        private_headers: Vec::new(),
    };
    if std::env::var_os("BETTERNOTES_NO_DESKTOP_WIDGETS").is_some() {
        return none;
    }
    let (Some(prefix), Some(headers), Some(libs), Some(version)) = (
        qmake_query("QT_INSTALL_PREFIX"),
        qmake_query("QT_INSTALL_HEADERS"),
        qmake_query("QT_INSTALL_LIBS"),
        qmake_query("QT_VERSION"),
    ) else {
        return none;
    };
    // LayerShellQt uses Qt's private Wayland API, so it must be built for
    // this very Qt: it is looked for next to it, or where
    // BETTERNOTES_LAYER_SHELL_PREFIX says (packaging/linux/build-layer-shell-qt.sh).
    let (layer_include, layer_libs) = match std::env::var_os("BETTERNOTES_LAYER_SHELL_PREFIX") {
        Some(own) => (Path::new(&own).join("include"), Path::new(&own).join("lib")),
        None => (Path::new(&prefix).join("include"), PathBuf::from(&libs)),
    };
    let layer_shell = (layer_include.join("LayerShellQt/window.h").is_file()
        && layer_libs.join("libLayerShellQtInterface.so").exists())
    .then_some((layer_include, layer_libs));
    let gui = Path::new(&headers).join("QtGui").join(&version);
    let core = Path::new(&headers).join("QtCore").join(&version);
    let private_headers = if gui.join("QtGui/qpa/qplatformwindow_p.h").is_file() {
        vec![
            gui.clone(),
            gui.join("QtGui"),
            core.clone(),
            core.join("QtCore"),
        ]
    } else {
        Vec::new()
    };
    DesktopWidgetSupport {
        layer_shell,
        private_headers,
    }
}

fn main() {
    println!("cargo:rerun-if-changed=src/protocols");
    let widgets = desktop_widget_support();
    let builder = CxxQtBuilder::new_qml_module(QmlModule::new("BetterNotes.App"))
        .file("src/bridge.rs")
        .file("src/notes_bridge.rs")
        .cpp_file("src/platform_helper.cpp")
        .cpp_file("src/text_formatter.h")
        .cpp_file("src/text_formatter.cpp")
        .cpp_file("src/language_support.h")
        .cpp_file("src/language_support.cpp")
        .cpp_file("src/key_sequences.h")
        .cpp_file("src/key_sequences.cpp")
        .cpp_file("src/image_animator.h")
        .cpp_file("src/image_animator.cpp")
        .cpp_file("src/desktop_widgets.h")
        .cpp_file("src/desktop_widgets.cpp")
        .cpp_file("src/window_placement.h")
        .cpp_file("src/window_placement.cpp")
        .qrc("../qml/qml.qrc")
        .qt_module("Gui")
        .qt_module("Quick")
        .qt_module("Widgets")
        .qt_module("DBus");
    // SAFETY: only adds include directories and preprocessor definitions.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            if let Some((include, _)) = &widgets.layer_shell {
                cc.include(include);
                cc.define("BETTERNOTES_LAYER_SHELL", None);
            }
            if !widgets.private_headers.is_empty() {
                for dir in &widgets.private_headers {
                    cc.include(dir);
                }
                cc.define("BETTERNOTES_XCB_WINDOW_TYPE", None);
            }
        })
    };
    builder.build();
    if let Some((_, libs)) = &widgets.layer_shell {
        println!("cargo:rustc-link-search=native={}", libs.display());
        println!("cargo:rustc-link-arg=-lLayerShellQtInterface");
        println!("cargo:rustc-link-arg=-lwayland-client");
    }

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
