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
}
