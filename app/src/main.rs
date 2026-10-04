mod bridge;
mod engine;
mod notes_bridge;
mod platform;

use betternotes_core::{
    handle_domain_request, is_server_running, paths, send_request, IpcAction, IpcErrorKind,
    IpcRequest, IpcResponse, IpcServer, NoteStore, Password,
};
use cxx_qt_lib::QGuiApplication;
use engine::{load_engine, MAIN_QML};
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// Exit status of `show` and `update` when the master password given is wrong.
const EXIT_WRONG_PASSWORD: u8 = 3;
/// Exit status of `show` and `update` for a locked note given no password.
const EXIT_LOCKED: u8 = 4;

/// Subcommands whose arguments may be arbitrary text, such as a note body of
/// "-v". Global flags are only looked for outside of them.
const SUBCOMMANDS: &[&str] = &[
    "new",
    "list",
    "search",
    "show",
    "archive",
    "update",
    "open",
    "backup",
    "restore",
    "export",
    "import",
    "install",
    "uninstall",
];

fn run() -> Result<i32, &'static str> {
    // Qt picks the native platform: Wayland on a Wayland session, X11 on an X11
    // session. QT_QPA_PLATFORM still overrides it.
    //
    // This used to force xcb so notes could restore exact screen positions,
    // which Wayland does not let a client choose. Under XWayland, though, the
    // compositor shows frames whose content lags the window size during an
    // interactive resize, so dragging a note's edge tore and smeared. Native
    // Wayland only shows a new size once the client has drawn it. The cost is
    // that the compositor places notes on Wayland; layers are handled by the
    // desktop integration (see DesktopEnvironment::supports_note_layers).
    let mut app = QGuiApplication::new();
    let mut app = app.as_mut().ok_or("could not create the Qt application")?;
    app.as_mut()
        .set_application_name(&betternotes_core::APPLICATION_NAME.into());
    app.as_mut()
        .set_application_version(&betternotes_core::APPLICATION_VERSION.into());
    // Names the installed desktop entry. On Wayland this becomes the app_id, so
    // the desktop shows the right name and icon for the app's windows.
    QGuiApplication::set_desktop_file_name(&betternotes_core::APPLICATION_ID.into());
    if !notes_bridge::ffi::platformSetApplicationIcon() {
        eprintln!("BetterNotes: the bundled application icon could not be loaded");
    }

    // Configure Linux desktop window manager rules/scripts (e.g. skip taskbar on KDE Plasma)
    betternotes_core::DesktopEnvironment::detect().setup_window_manager_integration();

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
    println!("      --body <TEXT|->     Content; \"-\" reads it from standard input");
    println!("      --id-only           Print only the new note's numeric ID");
    println!("      --no-open           Do not open the note's sticky window");
    println!("  list [-a, --archived]   List notes with tags, priority, and summary");
    println!("  search <QUERY>          Search note titles and contents using FTS5");
    println!("  show <ID> [--password-stdin]");
    println!("                          Display full content and metadata of a note");
    println!("  archive <ID> [--unarchive] Archive or unarchive a note");
    println!("  update <ID> [--title <TITLE>] [--body <TEXT|->] [--password-stdin]");
    println!("                          Change a note's title and/or content without the GUI;");
    println!("                          \"-\" reads the content from standard input");
    println!("      --password-stdin    Read the master password for a locked note from the");
    println!("                          first line of standard input (before any --body -)");
    println!("  open <ID>               Show a note's sticky window, starting BetterNotes in the");
    println!("                          background if it is not running");
    println!(
        "  backup [TARGET_DIR]     Create crash-safe atomic backup of database and attachments"
    );
    println!("  restore <BACKUP_DIR>    Safely restore backup with pre-restore safety snapshot");
    println!("  export [OUTPUT_PATH]    Export all notes to JSON file or Markdown directory");
    println!("  import <INPUT_FILE>     Import notes from JSON or Markdown file");
    println!("  install                 Add BetterNotes to your applications menu (no root)");
    println!("  uninstall               Remove it from the menu again; notes are kept\n");
    println!("Options:");
    println!(
        "  -b, --background        Start in background (restore notes and tray, hide main window)"
    );
    println!("  -q, --quick-capture     Open Quick Capture scratchpad (or focus running instance)");
    println!("  -o, --open FILE...      Open text, Markdown or image files as new notes");
    println!(
        "  -d, --diagnostics       Print desktop, compositor and display server diagnostic report"
    );
    println!("  -h, --help              Print this help message");
    println!("  -v, --version           Print version information\n");
    println!("Exit status of show and update:");
    println!(
        "  0 success, 1 error (such as a missing note), {EXIT_WRONG_PASSWORD} wrong password,"
    );
    println!("  {EXIT_LOCKED} the note is locked and no password was given");
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

/// Takes the value that follows `flag`.
fn flag_value(args: &mut std::slice::Iter<'_, String>, flag: &str) -> Result<String, String> {
    args.next()
        .cloned()
        .ok_or_else(|| format!("{flag} needs a value"))
}

/// A note body given on the command line. "-" means standard input, so
/// callers can pass multi-line text without a temporary file.
fn read_body(value: String) -> Result<String, String> {
    if value != "-" {
        return Ok(value);
    }
    let mut text = String::new();
    std::io::stdin()
        .read_to_string(&mut text)
        .map_err(|e| format!("Could not read the note body from standard input: {e}"))?;
    // The newline that ends echo output or a heredoc is not part of the note.
    if text.ends_with('\n') {
        text.pop();
        if text.ends_with('\r') {
            text.pop();
        }
    }
    Ok(text)
}

/// `--password-stdin`: the master password is the first line of standard
/// input, so it stays out of the process list and shell history. Anything
/// after it is left for `--body -`.
fn read_password() -> Result<Password, String> {
    let mut line = String::with_capacity(128);
    std::io::stdin()
        .read_line(&mut line)
        .map_err(|e| format!("Could not read the password from standard input: {e}"))?;
    if line.ends_with('\n') {
        line.pop();
        if line.ends_with('\r') {
            line.pop();
        }
    }
    let password = Password::new(line);
    if password.expose().is_empty() {
        return Err("no password on standard input".to_string());
    }
    Ok(password)
}

/// The exit status for a failed `show` or `update`, telling a wrong or
/// missing password apart from other failures.
fn failure_status(response: &IpcResponse) -> std::process::ExitCode {
    match response.error {
        Some(IpcErrorKind::WrongPassword) => std::process::ExitCode::from(EXIT_WRONG_PASSWORD),
        Some(IpcErrorKind::Locked) => std::process::ExitCode::from(EXIT_LOCKED),
        None => std::process::ExitCode::FAILURE,
    }
}

struct NewCommand {
    title: String,
    content: String,
    id_only: bool,
    open: bool,
}

/// `new <TITLE> [CONTENT...] [--body <TEXT|->] [--id-only] [--no-open]`
fn parse_new_command(args: &[String]) -> Result<NewCommand, String> {
    let mut positional = Vec::new();
    let mut body = None;
    let mut id_only = false;
    let mut open = true;
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--body" => body = Some(flag_value(&mut args, "--body")?),
            "--id-only" => id_only = true,
            "--no-open" => open = false,
            "--" => positional.extend(args.by_ref().cloned()),
            _ => positional.push(arg.clone()),
        }
    }
    if positional.is_empty() {
        return Err("a title is required".to_string());
    }
    let title = positional.remove(0);
    let content = match body {
        Some(_) if !positional.is_empty() => {
            return Err("give the content either as CONTENT or with --body, not both".to_string())
        }
        Some(body) => read_body(body)?,
        None => positional.join(" "),
    };
    Ok(NewCommand {
        title,
        content,
        id_only,
        open,
    })
}

/// `show <ID> [--password-stdin]`
fn parse_show_command(args: &[String]) -> Result<IpcRequest, String> {
    let mut args = args.iter();
    let id_arg = args.next().ok_or("a note ID is required")?;
    let id = id_arg
        .parse::<i64>()
        .map_err(|_| format!("Invalid note ID: {id_arg}"))?;
    let mut password_stdin = false;
    for arg in args {
        match arg.as_str() {
            "--password-stdin" => password_stdin = true,
            other => return Err(format!("unknown argument: {other}")),
        }
    }
    let password = password_stdin.then(read_password).transpose()?;
    Ok(IpcRequest::ShowNote { id, password })
}

/// `update <ID> [--title <TITLE>] [--body <TEXT|->] [--password-stdin]`
fn parse_update_command(args: &[String]) -> Result<IpcRequest, String> {
    let mut args = args.iter();
    let id_arg = args.next().ok_or("a note ID is required")?;
    let id = id_arg
        .parse::<i64>()
        .map_err(|_| format!("Invalid note ID: {id_arg}"))?;
    let mut title = None;
    let mut body = None;
    let mut password_stdin = false;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--title" => title = Some(flag_value(&mut args, "--title")?),
            "--body" | "--content" => body = Some(flag_value(&mut args, arg)?),
            "--password-stdin" => password_stdin = true,
            other => return Err(format!("unknown argument: {other}")),
        }
    }
    if title.is_none() && body.is_none() {
        return Err("give --title, --body or both".to_string());
    }
    // The password line comes first on standard input, the content after it.
    let password = password_stdin.then(read_password).transpose()?;
    let content = body.map(read_body).transpose()?;
    Ok(IpcRequest::UpdateNote {
        id,
        title,
        content,
        password,
    })
}

/// How long `open` waits for an app it started to take requests.
const START_TIMEOUT: Duration = Duration::from_secs(15);

/// The command that starts this installation again as a separate process.
fn relaunch_command() -> Result<Command, String> {
    // An AppImage's files go away once the process that mounted them exits,
    // so the new process starts from the image file itself.
    if let Some(appimage) = std::env::var_os("APPIMAGE").filter(|path| !path.is_empty()) {
        return Ok(Command::new(appimage));
    }
    let exe = std::env::current_exe()
        .map_err(|e| format!("Could not find the BetterNotes executable: {e}"))?;
    // A Flatpak sandbox ends with the process it was started for. The Flatpak
    // portal starts the app in a sandbox of its own instead.
    if std::env::var_os("FLATPAK_ID").is_some() {
        let mut command = Command::new("flatpak-spawn");
        command.arg(exe);
        return Ok(command);
    }
    Ok(Command::new(exe))
}

/// Starts the app in the background as its own process and waits until it
/// takes requests, so the command that started it can return.
fn start_background_instance(socket_path: &Path) -> Result<(), String> {
    let mut command = relaunch_command()?;
    // Its own process group keeps it alive when the caller's group is
    // signalled. Its output goes nowhere: a caller reading this command's
    // output would otherwise wait until the app quits. The caller's
    // activation token is for the note window and goes with the request; a
    // token is used up by the first window that takes it.
    command
        .arg("--background")
        .env_remove("XDG_ACTIVATION_TOKEN")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0);
    let mut child = command
        .spawn()
        .map_err(|e| format!("Could not start BetterNotes: {e}"))?;
    let deadline = Instant::now() + START_TIMEOUT;
    while Instant::now() < deadline {
        if is_server_running(socket_path) {
            return Ok(());
        }
        if let Ok(Some(status)) = child.try_wait() {
            return Err(format!("BetterNotes exited while starting ({status})"));
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    // The socket comes up before the database or Qt is touched, so a copy
    // that never answered will not. Left running, every later `open` would
    // start another one. (Under Flatpak this stops flatpak-spawn; the app it
    // started in another sandbox is not reached by this signal.)
    let _ = child.kill();
    let _ = child.wait();
    Err("BetterNotes did not start in time".to_string())
}

/// `open <ID>`: the note's window in the running app, which is started first
/// when needed. The note is checked before anything is started.
fn open_note(socket_path: &Path, db_path: &Path, id: i64) -> Result<IpcResponse, String> {
    if !is_server_running(socket_path) {
        let store =
            NoteStore::open(db_path).map_err(|e| format!("Failed to open database: {e}"))?;
        if let Err(response) = betternotes_core::require_openable_note(&store, id) {
            return Ok(response);
        }
        drop(store);
        start_background_instance(socket_path)?;
    }
    // A launcher or widget that runs this command for a click passes its
    // xdg-activation token in the environment.
    let activation_token = std::env::var("XDG_ACTIVATION_TOKEN")
        .ok()
        .and_then(|token| betternotes_core::valid_activation_token(&token));
    let request = IpcRequest::OpenNote {
        id,
        activation_token,
    };
    send_request(socket_path, &request).map_err(|e| format!("IPC error: {e}"))
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
    let global_flags: &[String] = match args.get(1) {
        Some(command) if SUBCOMMANDS.contains(&command.as_str()) => &[],
        _ => &args,
    };
    if global_flags.iter().any(|a| a == "-h" || a == "--help") {
        print_help();
        return std::process::ExitCode::SUCCESS;
    }
    if global_flags.iter().any(|a| a == "-v" || a == "--version") {
        println!(
            "{} {}",
            betternotes_core::APPLICATION_NAME,
            betternotes_core::APPLICATION_VERSION
        );
        return std::process::ExitCode::SUCCESS;
    }
    if global_flags
        .iter()
        .any(|a| a == "-d" || a == "--diagnostics")
    {
        let report = betternotes_core::DesktopReport::current();
        println!("{}", report.format_report());
        return std::process::ExitCode::SUCCESS;
    }

    if args.len() >= 2 && (args[1] == "install" || args[1] == "uninstall") {
        let result = if args[1] == "install" {
            betternotes_core::install::install_for_current_user()
        } else {
            betternotes_core::install::uninstall_for_current_user()
        };
        return match result {
            Ok(message) => {
                println!("{message}");
                std::process::ExitCode::SUCCESS
            }
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                std::process::ExitCode::FAILURE
            }
        };
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
        let command = match parse_new_command(&args[2..]) {
            Ok(command) => command,
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                eprintln!(
                    "Usage: betternotes new <TITLE> [CONTENT] [--body <TEXT|->] [--id-only] [--no-open]"
                );
                return std::process::ExitCode::FAILURE;
            }
        };
        let req = IpcRequest::NewNote {
            title: command.title,
            content: command.content,
            open: command.open,
        };
        return match dispatch_domain_command(&socket_path, &db_path, &req) {
            Ok(res) => {
                if res.success {
                    let id = res
                        .data
                        .as_ref()
                        .and_then(|data| data.get("id"))
                        .and_then(|id| id.as_i64());
                    match (command.id_only, id, res.message) {
                        (true, Some(id), _) => println!("{id}"),
                        (false, _, Some(msg)) => println!("{msg}"),
                        _ => {}
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
        let req = match parse_show_command(&args[2..]) {
            Ok(req) => req,
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                eprintln!("Usage: betternotes show <ID> [--password-stdin]");
                return std::process::ExitCode::FAILURE;
            }
        };
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
                    failure_status(&res)
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

    // CLI Command: update
    if args.len() >= 2 && args[1] == "update" {
        let req = match parse_update_command(&args[2..]) {
            Ok(req) => req,
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                eprintln!(
                    "Usage: betternotes update <ID> [--title <TITLE>] [--body <TEXT|->] [--password-stdin]"
                );
                return std::process::ExitCode::FAILURE;
            }
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
                        res.message.as_deref().unwrap_or("Failed to update note")
                    );
                    failure_status(&res)
                }
            }
            Err(e) => {
                eprintln!("BetterNotes: {e}");
                std::process::ExitCode::FAILURE
            }
        };
    }

    // CLI Command: open
    if args.len() >= 2 && args[1] == "open" {
        if args.len() != 3 {
            eprintln!("Usage: betternotes open <ID>");
            return std::process::ExitCode::FAILURE;
        }
        let id = match args[2].parse::<i64>() {
            Ok(n) => n,
            Err(_) => {
                eprintln!("Invalid note ID: {}", args[2]);
                return std::process::ExitCode::FAILURE;
            }
        };
        return match open_note(&socket_path, &db_path, id) {
            Ok(res) => {
                if res.success {
                    if let Some(msg) = res.message {
                        println!("{msg}");
                    }
                    std::process::ExitCode::SUCCESS
                } else {
                    eprintln!(
                        "Error: {}",
                        res.message.as_deref().unwrap_or("Failed to open note")
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

    // Files to open as notes ("Open with" passes them after --open).
    let open_paths: Vec<String> = match args.iter().position(|a| a == "-o" || a == "--open") {
        Some(index) => betternotes_core::open_files::requested_paths(
            &args[index + 1..],
            &std::env::current_dir().unwrap_or_else(|_| PathBuf::from("/")),
        )
        .iter()
        .map(|path| path.to_string_lossy().into_owned())
        .collect(),
        None => Vec::new(),
    };

    // Single-instance coordination for GUI launch
    if is_server_running(&socket_path) {
        if !open_paths.is_empty() {
            let _ = send_request(&socket_path, &IpcRequest::OpenFiles { paths: open_paths });
            println!("BetterNotes: opened the files in the running instance.");
            return std::process::ExitCode::SUCCESS;
        }
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
            IpcRequest::NewNote { open, .. } => {
                let res = betternotes_core::handle_domain_request(&mut store, &req);
                if res.success {
                    if let Some(data) = &res.data {
                        if let Some(id) = data.get("id").and_then(|v| v.as_i64()) {
                            // A note created without its window still shows in the library.
                            let action = if *open {
                                IpcAction::OpenNote {
                                    id,
                                    activation_token: None,
                                }
                            } else {
                                IpcAction::Reload
                            };
                            betternotes_core::global_ipc_queue()
                                .lock()
                                .unwrap()
                                .push_back(action);
                        }
                    }
                }
                res
            }
            IpcRequest::UpdateNote { id, .. } => {
                let res = betternotes_core::handle_domain_request(&mut store, &req);
                if res.success {
                    betternotes_core::global_ipc_queue()
                        .lock()
                        .unwrap()
                        .push_back(IpcAction::NoteChanged(*id));
                }
                res
            }
            // The GUI opens it, asking for the password first when it is locked.
            IpcRequest::OpenNote {
                id,
                activation_token,
            } => match betternotes_core::require_openable_note(&store, *id) {
                Ok(()) => {
                    let activation_token = activation_token
                        .as_deref()
                        .and_then(betternotes_core::valid_activation_token);
                    betternotes_core::global_ipc_queue()
                        .lock()
                        .unwrap()
                        .push_back(IpcAction::OpenNote {
                            id: *id,
                            activation_token,
                        });
                    IpcResponse::ok_msg(
                        format!("Opened note #{id}"),
                        Some(serde_json::json!({ "id": id })),
                    )
                }
                Err(response) => response,
            },
            // Paths from another process: absolute, and not too many. The GUI
            // checks each file before reading it.
            IpcRequest::OpenFiles { paths } => {
                let paths: Vec<String> = paths
                    .iter()
                    .filter(|path| Path::new(path).is_absolute())
                    .take(betternotes_core::open_files::MAX_FILES)
                    .cloned()
                    .collect();
                if paths.is_empty() {
                    return IpcResponse::err("No absolute file paths to open");
                }
                betternotes_core::global_ipc_queue()
                    .lock()
                    .unwrap()
                    .push_back(IpcAction::OpenFiles(paths));
                IpcResponse::ok_msg("Opening files", None)
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
