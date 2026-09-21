//! Thin adapter for application identity and the isolated Qt platform policy.

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
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

        /// Files given with --open when the app started, as absolute paths.
        #[qinvokable]
        #[cxx_name = "startFiles"]
        fn start_files(&self) -> QStringList;

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

        #[qinvokable]
        #[cxx_name = "isInstalled"]
        fn is_installed(&self) -> bool;

        #[qinvokable]
        #[cxx_name = "canInstall"]
        fn can_install(&self) -> bool;

        /// Installs or uninstalls for this user; returns "" on success or the
        /// reason it failed.
        #[qinvokable]
        #[cxx_name = "setInstalled"]
        fn set_installed(&self, installed: bool) -> QString;
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

    pub fn start_files(&self) -> cxx_qt_lib::QStringList {
        let args: Vec<String> = std::env::args().collect();
        let Some(index) = args.iter().position(|a| a == "-o" || a == "--open") else {
            return cxx_qt_lib::QStringList::default();
        };
        betternotes_core::open_files::requested_paths(
            &args[index + 1..],
            &std::env::current_dir().unwrap_or_else(|_| "/".into()),
        )
        .iter()
        .map(|path| cxx_qt_lib::QString::from(path.to_string_lossy().as_ref()))
        .collect()
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

    pub fn is_installed(&self) -> bool {
        betternotes_core::install::InstallLayout::current()
            .is_ok_and(|layout| betternotes_core::install::is_installed(&layout))
    }

    pub fn can_install(&self) -> bool {
        !matches!(
            betternotes_core::install::InstallSource::detect(),
            Ok(betternotes_core::install::InstallSource::Managed) | Err(_)
        )
    }

    pub fn set_installed(&self, installed: bool) -> cxx_qt_lib::QString {
        let result = if installed {
            betternotes_core::install::install_for_current_user()
        } else {
            betternotes_core::install::uninstall_for_current_user()
        };
        match result {
            Ok(_) => cxx_qt_lib::QString::default(),
            Err(error) => error.to_string().into(),
        }
    }
}
