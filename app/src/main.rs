mod bridge;
mod engine;
mod notes_bridge;
mod platform;

use betternotes_core::{
    handle_domain_request, is_server_running, paths, send_request, IpcAction, IpcRequest,
    IpcResponse, IpcServer, NoteStore,
};
use cxx_qt_lib::QGuiApplication;
use engine::{load_engine, MAIN_QML};
use std::path::{Path, PathBuf};

fn run() -> Result<i32, &'static str> {
    // If the user hasn't explicitly set QT_QPA_PLATFORM:
    // Desktop sticky notes require reliable window positioning and restoration across sessions.
    // Native Wayland xdg-shell strictly forbids clients from requesting their screen coordinates.
    // Using xcb (X11/XWayland) with wayland fallback provides exact desktop coordinate persistence
    // while gracefully functioning on pure Wayland environments.
    if std::env::var_os("QT_QPA_PLATFORM").is_none() {
        std::env::set_var("QT_QPA_PLATFORM", "xcb;wayland");
    }
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
    println!("Usage: betternotes [COMMAND] [OPTIONS]\n");
    println!("Commands:");
    println!("  new <TITLE> [CONTENT]   Create a new note (opens in GUI if running)");
    println!("  list [-a, --archived]   List notes with tags, priority, and summary");
    println!("  search <QUERY>          Search note titles and contents using FTS5");
    println!("  show <ID>               Display full content and metadata of a note");
    println!("  archive <ID> [--unarchive] Archive or unarchive a note");
    println!(
        "  backup [TARGET_DIR]     Create crash-safe atomic backup of database and attachments"
    );
    println!("  restore <BACKUP_DIR>    Safely restore backup with pre-restore safety snapshot");
    println!("  export [OUTPUT_PATH]    Export all notes to JSON file or Markdown directory");
    println!("  import <INPUT_FILE>     Import notes from JSON or Markdown file\n");
    println!("Options:");
    println!(
        "  -b, --background        Start in background (restore notes and tray, hide main window)"
    );
    println!("  -q, --quick-capture     Open Quick Capture scratchpad (or focus running instance)");
    println!(
        "  -d, --diagnostics       Print desktop, compositor and display server diagnostic report"
    );
    println!("  -h, --help              Print this help message");
    println!("  -v, --version           Print version information");
}

fn resolve_data_paths() -> Result<(PathBuf, PathBuf, PathBuf), String> {
    let db_path =
        paths::database_path().map_err(|e| format!("Could not resolve database path: {e}"))?;
    let data_dir = db_path.parent().unwrap().to_path_buf();
    let socket_path =
        paths::ipc_socket_path().map_err(|e| format!("Could not resolve IPC socket path: {e}"))?;
    Ok((data_dir, db_path, socket_path))
}

fn dispatch_domain_command(
    socket_path: &Path,
    db_path: &Path,
    request: &IpcRequest,
) -> Result<IpcResponse, String> {
    if is_server_running(socket_path) {
        send_request(socket_path, request).map_err(|e| format!("IPC error: {e}"))
    } else {
        let mut store =
            NoteStore::open(db_path).map_err(|e| format!("Failed to open database: {e}"))?;
        Ok(handle_domain_request(&mut store, request))
    }
}

fn print_notes_table(data: Option<&serde_json::Value>) {
    let empty = Vec::new();
    let notes = data.and_then(|d| d.as_array()).unwrap_or(&empty);
    if notes.is_empty() {
        println!("No notes found.");
        return;
    }
    println!(
        "{:<6} {:<10} {:<20} {:<30}",
        "ID", "PRIORITY", "TAGS", "TITLE"
    );
    println!("{}", "-".repeat(70));
    for note in notes {
        let id = note.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
        let title = note
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("Untitled");
        let prio = match note.get("priority").and_then(|v| v.as_i64()).unwrap_or(0) {
            1 => "Low",
            2 => "High",
            3 => "Urgent",
            _ => "Normal",
        };
        let tags: Vec<String> = note
            .get("tags")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|t| t.as_str().map(|s| format!("#{s}")))
                    .collect()
            })
            .unwrap_or_default();
        let tags_str = if tags.is_empty() {
            "-".to_string()
        } else {
            tags.join(" ")
        };
        let is_archived = note
            .get("is_archived")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let title_display = if is_archived {
            format!("[Archived] {title}")
        } else {
            title.to_string()
        };
        println!(
            "{:<6} {:<10} {:<20} {:<30}",
            id, prio, tags_str, title_display
        );
    }
}

fn print_search_results(query: &str, data: Option<&serde_json::Value>) {
    let empty = Vec::new();
    let hits = data.and_then(|d| d.as_array()).unwrap_or(&empty);
    if hits.is_empty() {
        println!("No notes found matching \"{query}\".");
        return;
    }
    println!("Found {} note(s) matching \"{query}\":\n", hits.len());
    for hit in hits {
        let id = hit.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
        let title = hit
            .get("title")
            .and_then(|v| v.as_str())
            .unwrap_or("Untitled");
        let snippet = hit.get("snippet").and_then(|v| v.as_str()).unwrap_or("");
        println!("#{id}: {title}");
        if !snippet.is_empty() {
            println!("    {snippet}");
        }
    }
}

fn print_note_detail(data: Option<&serde_json::Value>) {
    let Some(note) = data else {
        println!("No note data available.");
        return;
    };
    let id = note.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
    let title = note
        .get("title")
        .and_then(|v| v.as_str())
        .unwrap_or("Untitled");
    let content = note.get("content").and_then(|v| v.as_str()).unwrap_or("");
    let is_pinned = note
        .get("is_pinned")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let is_archived = note
        .get("is_archived")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let prio = match note.get("priority").and_then(|v| v.as_i64()).unwrap_or(0) {
        1 => "Low",
        2 => "High",
        3 => "Urgent",
        _ => "Normal",
    };
    let tags: Vec<String> = note
        .get("tags")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|t| t.as_str().map(|s| format!("#{s}")))
                .collect()
        })
        .unwrap_or_default();
    let tags_str = if tags.is_empty() {
        "none".to_string()
    } else {
        tags.join(", ")
    };

    println!("# Note #{id}: {title}");
    println!(
        "Priority: {prio} | Pinned: {is_pinned} | Archived: {is_archived} | Tags: {tags_str}\n"
    );
    println!("--- Content ---");
    println!("{content}");
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

    let (data_dir, db_path, socket_path) = match resolve_data_paths() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("BetterNotes: {e}");
            return std::process::ExitCode::FAILURE;
        }
    };

    // CLI Command: new
    if args.len() >= 2 && args[1] == "new" {
        if args.len() < 3 {
            eprintln!("Usage: betternotes new <TITLE> [CONTENT]");
            return std::process::ExitCode::FAILURE;
        }
        let title = args[2].clone();
        let content = if args.len() >= 4 {
            args[3..].join(" ")
        } else {
            String::new()
        };
        let req = IpcRequest::NewNote { title, content };
        return match dispatch_domain_command(&socket_path, &db_path, &req) {
            Ok(res) => {
                if res.success {
                    if let Some(msg) = res.message {
                        println!("{msg}");
                    }
                    std::process::ExitCode::SUCCESS
                } else {
                    eprintln!(
                        "Error: {}",
                        res.message.as_deref().unwrap_or("Failed to create note")
                    );
                    std::process::ExitCode::FAILURE
                }
            }
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                std::process::ExitCode::FAILURE
            }
        };
    }

    // CLI Command: list
    if args.len() >= 2 && args[1] == "list" {
        let include_archived = args.iter().any(|a| a == "-a" || a == "--archived");
        let req = IpcRequest::ListNotes { include_archived };
        return match dispatch_domain_command(&socket_path, &db_path, &req) {
            Ok(res) => {
                if res.success {
                    print_notes_table(res.data.as_ref());
                    std::process::ExitCode::SUCCESS
                } else {
                    eprintln!(
                        "Error: {}",
                        res.message.as_deref().unwrap_or("Failed to list notes")
                    );
                    std::process::ExitCode::FAILURE
                }
            }
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                std::process::ExitCode::FAILURE
            }
        };
    }

    // CLI Command: search
    if args.len() >= 2 && args[1] == "search" {
        if args.len() < 3 {
            eprintln!("Usage: betternotes search <QUERY>");
            return std::process::ExitCode::FAILURE;
        }
        let query = args[2..].join(" ");
        let req = IpcRequest::SearchNotes {
            query: query.clone(),
        };
        return match dispatch_domain_command(&socket_path, &db_path, &req) {
            Ok(res) => {
                if res.success {
                    print_search_results(&query, res.data.as_ref());
                    std::process::ExitCode::SUCCESS
                } else {
                    eprintln!(
                        "Error: {}",
                        res.message.as_deref().unwrap_or("Search failed")
                    );
                    std::process::ExitCode::FAILURE
                }
            }
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                std::process::ExitCode::FAILURE
            }
        };
    }

    // CLI Command: show
    if args.len() >= 2 && args[1] == "show" {
        if args.len() < 3 {
            eprintln!("Usage: betternotes show <ID>");
            return std::process::ExitCode::FAILURE;
        }
        let id = match args[2].parse::<i64>() {
            Ok(n) => n,
            Err(_) => {
                eprintln!("Invalid note ID: {}", args[2]);
                return std::process::ExitCode::FAILURE;
            }
        };
        let req = IpcRequest::ShowNote { id };
        return match dispatch_domain_command(&socket_path, &db_path, &req) {
            Ok(res) => {
                if res.success {
                    print_note_detail(res.data.as_ref());
                    std::process::ExitCode::SUCCESS
                } else {
                    eprintln!(
                        "Error: {}",
                        res.message.as_deref().unwrap_or("Note not found")
                    );
                    std::process::ExitCode::FAILURE
                }
            }
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                std::process::ExitCode::FAILURE
            }
        };
    }

    // CLI Command: archive
    if args.len() >= 2 && args[1] == "archive" {
        if args.len() < 3 {
            eprintln!("Usage: betternotes archive <ID> [--unarchive]");
            return std::process::ExitCode::FAILURE;
        }
        let id = match args[2].parse::<i64>() {
            Ok(n) => n,
            Err(_) => {
                eprintln!("Invalid note ID: {}", args[2]);
                return std::process::ExitCode::FAILURE;
            }
        };
        let unarchive = args.iter().any(|a| a == "--unarchive");
        let req = IpcRequest::ArchiveNote {
            id,
            archived: !unarchive,
        };
        return match dispatch_domain_command(&socket_path, &db_path, &req) {
            Ok(res) => {
                if res.success {
                    if let Some(msg) = res.message {
                        println!("{msg}");
                    }
                    std::process::ExitCode::SUCCESS
                } else {
                    eprintln!(
                        "Error: {}",
                        res.message.as_deref().unwrap_or("Archive operation failed")
                    );
                    std::process::ExitCode::FAILURE
                }
            }
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                std::process::ExitCode::FAILURE
            }
        };
    }

    // CLI Command: backup
    if args.len() >= 2 && args[1] == "backup" {
        let target = if args.len() >= 3 {
            PathBuf::from(&args[2])
        } else {
            std::env::current_dir().unwrap_or(data_dir.clone())
        };
        let store = match NoteStore::open(&db_path) {
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

    // CLI Command: restore
    if args.len() >= 3 && args[1] == "restore" {
        let backup_dir = PathBuf::from(&args[2]);
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

    // CLI Command: export
    if args.len() >= 2 && args[1] == "export" {
        let output = if args.len() >= 3 {
            PathBuf::from(&args[2])
        } else {
            PathBuf::from("betternotes_export.json")
        };
        let store = match NoteStore::open(&db_path) {
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

    // CLI Command: import
    if args.len() >= 3 && args[1] == "import" {
        let input = PathBuf::from(&args[2]);
        let store = match NoteStore::open(&db_path) {
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

    // Single-instance coordination for GUI launch
    if is_server_running(&socket_path) {
        if args.iter().any(|a| a == "-q" || a == "--quick-capture") {
            let _ = send_request(&socket_path, &IpcRequest::QuickCapture);
            println!("BetterNotes: opened Quick Capture in running instance.");
            return std::process::ExitCode::SUCCESS;
        }
        if args.iter().any(|a| a == "-b" || a == "--background") {
            println!("BetterNotes: application is already running in background.");
            return std::process::ExitCode::SUCCESS;
        }
        let _ = send_request(&socket_path, &IpcRequest::Activate);
        println!("BetterNotes: activated running instance window.");
        return std::process::ExitCode::SUCCESS;
    }

    // Primary instance starts the IPC server
    let db_path_for_ipc = db_path.clone();
    let _ipc_server = match IpcServer::start(socket_path.clone(), move |req| {
        let mut store = match NoteStore::open(&db_path_for_ipc) {
            Ok(s) => s,
            Err(e) => return IpcResponse::err(format!("Database error: {e}")),
        };
        match &req {
            IpcRequest::Activate => {
                betternotes_core::global_ipc_queue()
                    .lock()
                    .unwrap()
                    .push_back(IpcAction::Activate);
                IpcResponse::ok_msg("Window activated", None)
            }
            IpcRequest::QuickCapture => {
                betternotes_core::global_ipc_queue()
                    .lock()
                    .unwrap()
                    .push_back(IpcAction::QuickCapture);
                IpcResponse::ok_msg("Quick capture activated", None)
            }
            IpcRequest::NewNote { .. } => {
                let res = betternotes_core::handle_domain_request(&mut store, &req);
                if res.success {
                    if let Some(data) = &res.data {
                        if let Some(id) = data.get("id").and_then(|v| v.as_i64()) {
                            betternotes_core::global_ipc_queue()
                                .lock()
                                .unwrap()
                                .push_back(IpcAction::OpenNote(id));
                        }
                    }
                }
                res
            }
            IpcRequest::ArchiveNote { .. } => {
                let res = betternotes_core::handle_domain_request(&mut store, &req);
                if res.success {
                    betternotes_core::global_ipc_queue()
                        .lock()
                        .unwrap()
                        .push_back(IpcAction::Reload);
                }
                res
            }
            _ => betternotes_core::handle_domain_request(&mut store, &req),
        }
    }) {
        Ok(server) => Some(server),
        Err(e) => {
            eprintln!("BetterNotes: Warning - could not start IPC listener: {e}");
            None
        }
    };

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
