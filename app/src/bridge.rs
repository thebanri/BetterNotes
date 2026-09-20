//! Thin Qt adapter. Application identity is owned by the independent Rust core.

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
    }
}

#[derive(Default)]
pub struct ApplicationInfoRust;

impl ffi::ApplicationInfo {
    pub fn name(&self) -> cxx_qt_lib::QString {
        betternotes_core::APPLICATION_NAME.into()
    }

    pub fn version(&self) -> cxx_qt_lib::QString {
        betternotes_core::APPLICATION_VERSION.into()
    }
}
