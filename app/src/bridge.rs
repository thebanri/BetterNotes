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
}
