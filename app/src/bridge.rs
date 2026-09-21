//! Thin adapter for application identity and the isolated Qt platform policy.

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type ApplicationInfo = super::ApplicationInfoRust;

        #[qinvokable]
        fn name(&self) -> QString;

        #[qinvokable]
        fn version(&self) -> QString;

        #[qinvokable]
        #[cxx_name = "canPositionWindows"]
        fn can_position_windows(&self, plugin: QString) -> bool;

        #[qinvokable]
        #[cxx_name = "startInBackground"]
        fn start_in_background(&self) -> bool;

        #[qinvokable]
        #[cxx_name = "startQuickCapture"]
        fn start_quick_capture(&self) -> bool;

        #[qinvokable]
        #[cxx_name = "desktopEnvironment"]
        fn desktop_environment(&self) -> QString;

        #[qinvokable]
        #[cxx_name = "displayServer"]
        fn display_server(&self) -> QString;

        #[qinvokable]
        #[cxx_name = "externalUrl"]
        fn external_url(&self, link: QString) -> QString;

        #[qinvokable]
        #[cxx_name = "supportsNoteLayers"]
        fn supports_note_layers(&self) -> bool;

        #[qinvokable]
        #[cxx_name = "isTilingCompositor"]
        fn is_tiling_compositor(&self) -> bool;

        #[qinvokable]
        #[cxx_name = "windowRuleHint"]
        fn window_rule_hint(&self) -> QString;

        #[qinvokable]
        #[cxx_name = "diagnosticsReport"]
        fn diagnostics_report(&self) -> QString;
    }
}

#[derive(Default)]
pub struct ApplicationInfoRust;

impl ffi::ApplicationInfo {
    pub fn can_position_windows(&self, plugin: cxx_qt_lib::QString) -> bool {
        crate::platform::can_position_windows(&plugin.to_string())
    }

    pub fn name(&self) -> cxx_qt_lib::QString {
        betternotes_core::APPLICATION_NAME.into()
    }

    pub fn version(&self) -> cxx_qt_lib::QString {
        betternotes_core::APPLICATION_VERSION.into()
    }

    pub fn start_in_background(&self) -> bool {
        std::env::args().any(|arg| arg == "--background" || arg == "-b")
    }

    pub fn start_quick_capture(&self) -> bool {
        std::env::args().any(|arg| arg == "--quick-capture" || arg == "-q")
    }

    pub fn desktop_environment(&self) -> cxx_qt_lib::QString {
        betternotes_core::DesktopEnvironment::detect()
            .name()
            .to_string()
            .into()
    }

    pub fn display_server(&self) -> cxx_qt_lib::QString {
        betternotes_core::DisplayServer::detect()
            .name()
            .to_string()
            .into()
    }

    /// The URL a clicked note link may open, or empty when it must not open.
    pub fn external_url(&self, link: cxx_qt_lib::QString) -> cxx_qt_lib::QString {
        betternotes_core::external_url(&link.to_string())
            .unwrap_or_default()
            .into()
    }

    pub fn supports_note_layers(&self) -> bool {
        betternotes_core::DesktopEnvironment::detect()
            .supports_note_layers(betternotes_core::DisplayServer::detect())
    }

    pub fn is_tiling_compositor(&self) -> bool {
        betternotes_core::DesktopEnvironment::detect().is_tiling()
    }

    pub fn window_rule_hint(&self) -> cxx_qt_lib::QString {
        betternotes_core::DesktopEnvironment::detect()
            .window_rule_hint()
            .unwrap_or("")
            .to_string()
            .into()
    }

    pub fn diagnostics_report(&self) -> cxx_qt_lib::QString {
        betternotes_core::DesktopReport::current()
            .format_report()
            .into()
    }
}
