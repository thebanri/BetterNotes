mod bridge;
mod engine;
mod notes_bridge;
mod platform;

use cxx_qt_lib::QGuiApplication;
use engine::{load_engine, MAIN_QML};

fn run() -> Result<i32, &'static str> {
    let mut app = QGuiApplication::new();
    let mut app = app.as_mut().ok_or("could not create the Qt application")?;
    app.as_mut()
        .set_application_name(&betternotes_core::APPLICATION_NAME.into());
    app.as_mut()
        .set_application_version(&betternotes_core::APPLICATION_VERSION.into());
    // Keep the engine alive until the event loop ends and drop it before Qt.
    let _engine = load_engine(MAIN_QML)?;
    eprintln!("BetterNotes: application window loaded");
    Ok(app.exec())
}

fn print_help() {
    println!(
        "{} v{}",
        betternotes_core::APPLICATION_NAME,
        betternotes_core::APPLICATION_VERSION
    );
    println!("Linux-first sticky notes and desktop workspace application.\n");
    println!("Usage: betternotes [OPTIONS]\n");
    println!("Options:");
    println!(
        "  -b, --background     Start in background (restore notes and tray, hide main window)"
    );
    println!("  -q, --quick-capture  Open Quick Capture scratchpad immediately");
    println!("  -h, --help           Print this help message");
    println!("  -v, --version        Print version information");
}

fn main() -> std::process::ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "-h" || a == "--help") {
        print_help();
        return std::process::ExitCode::SUCCESS;
    }
    if args.iter().any(|a| a == "-v" || a == "--version") {
        println!(
            "{} {}",
            betternotes_core::APPLICATION_NAME,
            betternotes_core::APPLICATION_VERSION
        );
        return std::process::ExitCode::SUCCESS;
    }

    match run() {
        Ok(0) => std::process::ExitCode::SUCCESS,
        Ok(code) => {
            eprintln!("BetterNotes: Qt event loop exited with code {code}");
            std::process::ExitCode::FAILURE
        }
        Err(error) => {
            eprintln!("BetterNotes: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}
