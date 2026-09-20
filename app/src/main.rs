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
    println!(
        "  -d, --diagnostics    Print desktop, compositor and display server diagnostic report"
    );
    println!("  -h, --help           Print this help message");
    println!("  -v, --version        Print version information");
    println!("\nCommands:");
    println!("  backup [TARGET_DIR]  Create crash-safe atomic backup of database and attachments");
    println!("  restore <BACKUP_DIR> Safely restore backup with pre-restore safety snapshot");
    println!("  export [OUTPUT_PATH] Export all notes to JSON file or Markdown directory");
    println!("  import <INPUT_FILE>  Import notes from JSON or Markdown file");
}

fn resolve_data_paths() -> Result<(std::path::PathBuf, std::path::PathBuf), String> {
    let db_path = betternotes_core::paths::database_path()
        .map_err(|e| format!("Could not resolve database path: {e}"))?;
    let data_dir = db_path.parent().unwrap().to_path_buf();
    Ok((data_dir, db_path))
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
    if args.iter().any(|a| a == "-d" || a == "--diagnostics") {
        let report = betternotes_core::DesktopReport::current();
        println!("{}", report.format_report());
        return std::process::ExitCode::SUCCESS;
    }

    if args.len() >= 2 && args[1] == "backup" {
        let (data_dir, db_path) = match resolve_data_paths() {
            Ok(p) => p,
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                return std::process::ExitCode::FAILURE;
            }
        };
        let target = if args.len() >= 3 {
            std::path::PathBuf::from(&args[2])
        } else {
            std::env::current_dir().unwrap_or(data_dir.clone())
        };
        let store = match betternotes_core::NoteStore::open(&db_path) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("BetterNotes: Cannot open database: {e}");
                return std::process::ExitCode::FAILURE;
            }
        };
        match betternotes_core::create_backup(store.raw_connection(), &data_dir, &target) {
            Ok(path) => {
                println!("Backup created successfully: {}", path.display());
                return std::process::ExitCode::SUCCESS;
            }
            Err(e) => {
                eprintln!("BetterNotes: Backup failed: {e}");
                return std::process::ExitCode::FAILURE;
            }
        }
    }

    if args.len() >= 3 && args[1] == "restore" {
        let (data_dir, _) = match resolve_data_paths() {
            Ok(p) => p,
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                return std::process::ExitCode::FAILURE;
            }
        };
        let backup_dir = std::path::PathBuf::from(&args[2]);
        match betternotes_core::restore_backup(&backup_dir, &data_dir) {
            Ok(_) => {
                println!(
                    "Backup restored successfully from: {}",
                    backup_dir.display()
                );
                return std::process::ExitCode::SUCCESS;
            }
            Err(e) => {
                eprintln!("BetterNotes: Restore failed: {e}");
                return std::process::ExitCode::FAILURE;
            }
        }
    }

    if args.len() >= 2 && args[1] == "export" {
        let (_, db_path) = match resolve_data_paths() {
            Ok(p) => p,
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                return std::process::ExitCode::FAILURE;
            }
        };
        let output = if args.len() >= 3 {
            std::path::PathBuf::from(&args[2])
        } else {
            std::path::PathBuf::from("betternotes_export.json")
        };
        let store = match betternotes_core::NoteStore::open(&db_path) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("BetterNotes: Cannot open database: {e}");
                return std::process::ExitCode::FAILURE;
            }
        };
        let notes = match store.all_notes_for_export() {
            Ok(n) => n,
            Err(e) => {
                eprintln!("BetterNotes: Failed reading notes: {e}");
                return std::process::ExitCode::FAILURE;
            }
        };
        let res = if output.extension().and_then(|s| s.to_str()) == Some("json") {
            betternotes_core::export_notes_json(&notes, &output)
        } else {
            betternotes_core::export_notes_markdown_dir(&notes, &output)
        };
        match res {
            Ok(_) => {
                println!("Exported {} notes to {}", notes.len(), output.display());
                return std::process::ExitCode::SUCCESS;
            }
            Err(e) => {
                eprintln!("BetterNotes: Export failed: {e}");
                return std::process::ExitCode::FAILURE;
            }
        }
    }

    if args.len() >= 3 && args[1] == "import" {
        let (_, db_path) = match resolve_data_paths() {
            Ok(p) => p,
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                return std::process::ExitCode::FAILURE;
            }
        };
        let input = std::path::PathBuf::from(&args[2]);
        let store = match betternotes_core::NoteStore::open(&db_path) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("BetterNotes: Cannot open database: {e}");
                return std::process::ExitCode::FAILURE;
            }
        };
        let res = if input.extension().and_then(|s| s.to_str()) == Some("json") {
            betternotes_core::import_notes_json(&store, &input)
        } else {
            betternotes_core::import_note_markdown_file(&store, &input)
        };
        match res {
            Ok(count) => {
                println!("Imported {count} note(s) from {}", input.display());
                return std::process::ExitCode::SUCCESS;
            }
            Err(e) => {
                eprintln!("BetterNotes: Import failed: {e}");
                return std::process::ExitCode::FAILURE;
            }
        }
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
