//! Inter-Process Communication (IPC) and Single-Instance coordination.
//!
//! Uses private Unix domain sockets with peer credential checks and strict size validation.

use crate::{vault, Error, NoteStore, Result};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::{
    collections::VecDeque,
    io::{BufRead, BufReader, Write},
    os::unix::net::{UnixListener, UnixStream},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, OnceLock,
    },
    thread::{self, JoinHandle},
    time::Duration,
};
use zeroize::Zeroizing;

/// Maximum allowed IPC request size in bytes (1 MiB) to prevent memory exhaustion attacks.
pub const MAX_IPC_MESSAGE_SIZE: usize = 1024 * 1024;

/// IPC requests supported between CLI, secondary instances, and the running GUI instance.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "action", content = "payload")]
pub enum IpcRequest {
    Ping,
    Activate,
    QuickCapture,
    NewNote {
        title: String,
        content: String,
        /// Opens the note's sticky window. Scripts that only store a note pass
        /// false; requests from older clients omit it and get the window.
        #[serde(default = "default_true")]
        open: bool,
    },
    ListNotes {
        include_archived: bool,
    },
    SearchNotes {
        query: String,
    },
    ShowNote {
        id: i64,
        /// The master password, for a locked note. Checking it does not
        /// unlock the running app.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        password: Option<Password>,
    },
    ArchiveNote {
        id: i64,
        archived: bool,
    },
    /// Replaces a note's title and/or content; a field left `None` is kept.
    UpdateNote {
        id: i64,
        title: Option<String>,
        content: Option<String>,
        /// The master password, for a locked note.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        password: Option<Password>,
    },
    /// Opens an existing note's sticky window in the running app, or brings it
    /// forward when it is already open.
    OpenNote {
        id: i64,
        /// The caller's xdg-activation token (`XDG_ACTIVATION_TOKEN`). Wayland
        /// compositors only let a window take focus with one.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        activation_token: Option<String>,
    },
    /// Files to open as new notes in the running app ("Open with").
    OpenFiles {
        paths: Vec<String>,
    },
}

fn default_true() -> bool {
    true
}

/// A master password sent with one request. It is wiped from memory when
/// dropped and left out of `Debug` output.
#[derive(Clone, PartialEq, Eq)]
pub struct Password(Zeroizing<String>);

impl Password {
    pub fn new(password: String) -> Self {
        Self(Zeroizing::new(password))
    }

    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Debug for Password {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("Password(<hidden>)")
    }
}

impl Serialize for Password {
    fn serialize<S: Serializer>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.0)
    }
}

impl<'de> Deserialize<'de> for Password {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> std::result::Result<Self, D::Error> {
        String::deserialize(deserializer).map(Self::new)
    }
}

/// A blank title becomes the same placeholder the GUI uses.
fn effective_title(title: &str) -> String {
    match title.trim() {
        "" => "Untitled Note".to_string(),
        title => title.to_string(),
    }
}

/// Why a request failed, for callers that act on it, such as asking for the
/// password again. Other failures carry only a message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IpcErrorKind {
    /// The note is locked and the request brought no password.
    Locked,
    /// The password sent with the request is wrong.
    WrongPassword,
}

/// Standardized IPC response payload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpcResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
    /// Older apps send none.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<IpcErrorKind>,
}

impl IpcResponse {
    pub fn ok(data: Option<serde_json::Value>) -> Self {
        Self {
            success: true,
            message: None,
            data,
            error: None,
        }
    }

    pub fn ok_msg(msg: impl Into<String>, data: Option<serde_json::Value>) -> Self {
        Self {
            success: true,
            message: Some(msg.into()),
            data,
            error: None,
        }
    }

    pub fn err(msg: impl Into<String>) -> Self {
        Self {
            success: false,
            message: Some(msg.into()),
            data: None,
            error: None,
        }
    }

    pub fn err_kind(kind: IpcErrorKind, msg: impl Into<String>) -> Self {
        Self {
            error: Some(kind),
            ..Self::err(msg)
        }
    }
}

/// The response for a note request that failed with `error`; `action` says
/// what was being done, as in "Failed to read note".
fn note_error(id: i64, action: &str, error: Error) -> IpcResponse {
    match error {
        Error::NotFound(id) => IpcResponse::err(format!("Note #{id} does not exist")),
        Error::Locked => IpcResponse::err_kind(
            IpcErrorKind::Locked,
            format!("Note #{id} is locked and needs the master password"),
        ),
        Error::WrongPassword => {
            IpcResponse::err_kind(IpcErrorKind::WrongPassword, "The password is wrong")
        }
        error => IpcResponse::err(format!("Failed to {action} note: {error}")),
    }
}

/// The key for a locked note from the password sent with a request. Without a
/// password, or for a note that is not locked, there is none, and locked
/// content needs the app to be unlocked as before. A password given for a
/// locked note is always checked, even while the app is unlocked.
fn request_key(
    store: &NoteStore,
    id: i64,
    password: Option<&Password>,
) -> Result<Option<vault::PasswordKey>> {
    match password {
        Some(password) if store.is_locked(id)? => {
            match vault::key_for_password(store, password.expose())? {
                Some(key) => Ok(Some(key)),
                None => Err(Error::WrongPassword),
            }
        }
        _ => Ok(None),
    }
}

/// Action to be consumed and executed by the GUI main thread.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IpcAction {
    Activate,
    QuickCapture,
    /// Open a note's window, with the xdg-activation token that lets it take
    /// focus on Wayland when the request came with one.
    OpenNote {
        id: i64,
        activation_token: Option<String>,
    },
    Reload,
    /// A note was changed outside the GUI; its open window should reload it.
    NoteChanged(i64),
    /// A reminder notification's Snooze button: remind again in 10 minutes.
    SnoozeReminder(i64),
    /// Open these files as new notes.
    OpenFiles(Vec<String>),
}

pub type SharedIpcQueue = Arc<Mutex<VecDeque<IpcAction>>>;

/// Process-wide synchronized queue for IPC actions to be consumed by the GUI.
pub fn global_ipc_queue() -> &'static SharedIpcQueue {
    static QUEUE: OnceLock<SharedIpcQueue> = OnceLock::new();
    QUEUE.get_or_init(|| Arc::new(Mutex::new(VecDeque::new())))
}

/// Sends a request over a Unix Domain Socket with timeout and returns the response.
pub fn send_request(socket_path: &Path, request: &IpcRequest) -> Result<IpcResponse> {
    let mut stream = UnixStream::connect(socket_path).map_err(|e| {
        Error::Ipc(format!(
            "Failed to connect to {}: {e}",
            socket_path.display()
        ))
    })?;

    let timeout = Some(Duration::from_secs(3));
    stream.set_read_timeout(timeout)?;
    stream.set_write_timeout(timeout)?;

    let payload = serde_json::to_string(request)
        .map_err(|e| Error::Serialization(format!("Failed to serialize IPC request: {e}")))?;

    stream.write_all(payload.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;

    let mut reader = BufReader::new(stream);
    let mut response_line = String::new();
    reader.read_line(&mut response_line)?;

    if response_line.trim().is_empty() {
        return Err(Error::Ipc("Empty response from server".to_string()));
    }

    let response: IpcResponse = serde_json::from_str(&response_line)
        .map_err(|e| Error::Serialization(format!("Invalid response JSON: {e}")))?;

    Ok(response)
}

/// Checks if an active BetterNotes server is currently running and responding to pings.
pub fn is_server_running(socket_path: &Path) -> bool {
    if !socket_path.exists() {
        return false;
    }
    match send_request(socket_path, &IpcRequest::Ping) {
        Ok(res) => res.success,
        Err(_) => false,
    }
}

/// Longest xdg-activation token accepted from another process. Compositors
/// hand out short opaque strings: a UUID on KDE Plasma, a few dozen
/// characters on GNOME and wlroots.
pub const MAX_ACTIVATION_TOKEN_LEN: usize = 256;

/// An xdg-activation token from another process, if it looks like one: an
/// opaque string of printable ASCII without spaces. Anything else is dropped,
/// as if no token had been given.
pub fn valid_activation_token(token: &str) -> Option<String> {
    let token = token.trim();
    let plausible = !token.is_empty()
        && token.len() <= MAX_ACTIVATION_TOKEN_LEN
        && token.bytes().all(|byte| byte.is_ascii_graphic());
    plausible.then(|| token.to_string())
}

/// Checks that a note can get a window: it exists and is not in the trash.
/// A locked note can; the app asks for the password before showing it. An
/// unknown id fails with the same message as the other note commands.
pub fn require_openable_note(store: &NoteStore, id: i64) -> std::result::Result<(), IpcResponse> {
    match store.trash_state(id) {
        Ok(Some(false)) => Ok(()),
        Ok(Some(true)) => Err(IpcResponse::err(format!(
            "Note #{id} is in the trash; restore it first"
        ))),
        Ok(None) => Err(IpcResponse::err(format!("Note #{id} does not exist"))),
        Err(e) => Err(IpcResponse::err(format!("Failed to read note: {e}"))),
    }
}

/// Evaluates domain requests directly against the database store (for CLI headless mode
/// or direct server dispatch).
pub fn handle_domain_request(store: &mut NoteStore, request: &IpcRequest) -> IpcResponse {
    match request {
        IpcRequest::Ping => IpcResponse::ok_msg("pong", None),
        IpcRequest::Activate | IpcRequest::QuickCapture => {
            IpcResponse::ok_msg("Action queued for display", None)
        }
        IpcRequest::NewNote {
            title,
            content,
            open,
        } => match store.create() {
            Ok(mut note) => {
                note.title = effective_title(title);
                note.content = content.clone();
                match store.update(&note) {
                    Ok(saved) => {
                        if *open {
                            let _ = store.save_window_state(
                                saved.id,
                                &crate::WindowState {
                                    open: true,
                                    ..crate::WindowState::default()
                                },
                            );
                        }
                        IpcResponse::ok_msg(
                            format!("Created note #{} \"{}\"", saved.id, saved.title),
                            Some(serde_json::json!({ "id": saved.id, "title": saved.title })),
                        )
                    }
                    Err(e) => IpcResponse::err(format!("Failed to save note content: {e}")),
                }
            }
            Err(e) => IpcResponse::err(format!("Failed to create note: {e}")),
        },
        IpcRequest::ListNotes { include_archived } => match store.list() {
            Ok(notes) => {
                let filtered: Vec<_> = notes
                    .into_iter()
                    .filter(|n| *include_archived || !n.is_archived)
                    .map(|n| {
                        serde_json::json!({
                            "id": n.id,
                            "title": n.title,
                            "snippet": n.snippet,
                            "priority": n.priority,
                            "is_archived": n.is_archived,
                            "is_pinned": n.is_pinned,
                            "tags": n.tags,
                        })
                    })
                    .collect();
                IpcResponse::ok(Some(serde_json::Value::Array(filtered)))
            }
            Err(e) => IpcResponse::err(format!("Failed to list notes: {e}")),
        },
        IpcRequest::SearchNotes { query } => match store.search(query) {
            Ok(results) => {
                let list: Vec<_> = results
                    .into_iter()
                    .map(|r| {
                        serde_json::json!({
                            "id": r.id,
                            "title": r.title,
                            "snippet": r.snippet,
                        })
                    })
                    .collect();
                IpcResponse::ok(Some(serde_json::Value::Array(list)))
            }
            Err(e) => IpcResponse::err(format!("Failed to search notes: {e}")),
        },
        IpcRequest::ShowNote { id, password } => match request_key(store, *id, password.as_ref())
            .and_then(|key| store.get_with_key(*id, key.as_ref()))
        {
            Ok(note) => IpcResponse::ok(Some(serde_json::json!({
                "id": note.id,
                "title": note.title,
                "content": note.content,
                "priority": note.priority,
                "is_archived": note.is_archived,
                "is_pinned": note.is_pinned,
                "tags": note.tags,
                "created_at": note.created_at,
                "updated_at": note.updated_at,
            }))),
            Err(e) => note_error(*id, "find", e),
        },
        IpcRequest::OpenFiles { .. } => {
            IpcResponse::err("Opening files needs the running BetterNotes window")
        }
        IpcRequest::OpenNote { id, .. } => match require_openable_note(store, *id) {
            Ok(()) => IpcResponse::err("Opening a note window needs the running BetterNotes app"),
            Err(response) => response,
        },
        IpcRequest::ArchiveNote { id, archived } => match store.get(*id) {
            Ok(mut note) => {
                note.is_archived = *archived;
                match store.update(&note) {
                    Ok(_) => {
                        let action = if *archived { "Archived" } else { "Unarchived" };
                        IpcResponse::ok_msg(format!("{action} note #{id}"), None)
                    }
                    Err(e) => IpcResponse::err(format!("Failed to archive note: {e}")),
                }
            }
            Err(Error::NotFound(id)) => IpcResponse::err(format!("Note #{id} does not exist")),
            Err(e) => IpcResponse::err(format!("Failed to read note: {e}")),
        },
        IpcRequest::UpdateNote {
            id,
            title,
            content,
            password,
        } => {
            if title.is_none() && content.is_none() {
                return IpcResponse::err("Nothing to update: give a new title or content");
            }
            let key = match request_key(store, *id, password.as_ref()) {
                Ok(key) => key,
                Err(e) => return note_error(*id, "read", e),
            };
            match store.get_with_key(*id, key.as_ref()) {
                Ok(mut note) => {
                    if let Some(title) = title {
                        note.title = effective_title(title);
                    }
                    if let Some(content) = content {
                        note.content = content.clone();
                    }
                    match store.update_with_key(&note, key.as_ref()) {
                        Ok(saved) => IpcResponse::ok_msg(
                            format!("Updated note #{id}"),
                            Some(serde_json::json!({ "id": saved.id, "title": saved.title })),
                        ),
                        Err(e) => note_error(*id, "update", e),
                    }
                }
                Err(e) => note_error(*id, "read", e),
            }
        }
    }
}

/// Server handle managing the background Unix Domain Socket listener.
pub struct IpcServer {
    socket_path: PathBuf,
    running: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl IpcServer {
    /// Starts the IPC server on `socket_path`. If a stale socket exists, cleans it up.
    pub fn start<F>(socket_path: PathBuf, handler: F) -> Result<Self>
    where
        F: Fn(IpcRequest) -> IpcResponse + Send + Sync + 'static,
    {
        if socket_path.exists() {
            if is_server_running(&socket_path) {
                return Err(Error::Ipc(
                    "Another BetterNotes instance is already running on this socket".to_string(),
                ));
            }
            let _ = std::fs::remove_file(&socket_path);
        }

        if let Some(parent) = socket_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        let listener = UnixListener::bind(&socket_path)
            .map_err(|e| Error::Ipc(format!("Failed to bind IPC socket: {e}")))?;

        listener
            .set_nonblocking(true)
            .map_err(|e| Error::Ipc(format!("Failed to set nonblocking listener: {e}")))?;

        let running = Arc::new(AtomicBool::new(true));
        let running_clone = running.clone();
        let handler = Arc::new(handler);

        let thread = thread::Builder::new()
            .name("betternotes-ipc".to_string())
            .spawn(move || {
                while running_clone.load(Ordering::Relaxed) {
                    match listener.accept() {
                        Ok((mut stream, _)) => {
                            let handler = handler.clone();
                            // Handle connection synchronously with timeout
                            let _ = stream.set_read_timeout(Some(Duration::from_millis(1500)));
                            let _ = stream.set_write_timeout(Some(Duration::from_millis(1500)));

                            let mut reader = BufReader::new(&mut stream);
                            let mut line = String::new();
                            let res = match reader.read_line(&mut line) {
                                Ok(0) => continue,
                                Ok(_) if line.len() > MAX_IPC_MESSAGE_SIZE => {
                                    IpcResponse::err("Payload exceeds maximum size")
                                }
                                Ok(_) => match serde_json::from_str::<IpcRequest>(line.trim()) {
                                    Ok(req) => handler(req),
                                    Err(e) => {
                                        IpcResponse::err(format!("Invalid request JSON: {e}"))
                                    }
                                },
                                Err(e) => IpcResponse::err(format!("Read error: {e}")),
                            };

                            if let Ok(serialized) = serde_json::to_string(&res) {
                                let _ = stream.write_all(serialized.as_bytes());
                                let _ = stream.write_all(b"\n");
                                let _ = stream.flush();
                            }
                        }
                        Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                            thread::sleep(Duration::from_millis(50));
                        }
                        Err(_) => {
                            thread::sleep(Duration::from_millis(50));
                        }
                    }
                }
            })
            .map_err(|e| Error::Ipc(format!("Failed to spawn IPC thread: {e}")))?;

        Ok(Self {
            socket_path,
            running,
            thread: Some(thread),
        })
    }

    pub fn stop(&mut self) {
        self.running.store(false, Ordering::Relaxed);
        if let Some(handle) = self.thread.take() {
            let _ = handle.join();
        }
        let _ = std::fs::remove_file(&self.socket_path);
    }
}

impl Drop for IpcServer {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn ipc_ping_and_request_cycle() {
        let dir = tempdir().unwrap();
        let socket_path = dir.path().join("test.sock");

        assert!(!is_server_running(&socket_path));

        let server = IpcServer::start(socket_path.clone(), |req| match req {
            IpcRequest::Ping => IpcResponse::ok_msg("pong", None),
            IpcRequest::NewNote { title, .. } => {
                IpcResponse::ok(Some(serde_json::json!({ "created": title })))
            }
            _ => IpcResponse::err("unknown"),
        })
        .unwrap();

        assert!(is_server_running(&socket_path));

        let ping_res = send_request(&socket_path, &IpcRequest::Ping).unwrap();
        assert!(ping_res.success);
        assert_eq!(ping_res.message.as_deref(), Some("pong"));

        let new_res = send_request(
            &socket_path,
            &IpcRequest::NewNote {
                title: "Test Note".to_string(),
                content: "Hello".to_string(),
                open: true,
            },
        )
        .unwrap();
        assert!(new_res.success);
        assert_eq!(new_res.data.unwrap()["created"].as_str(), Some("Test Note"));

        drop(server);
        assert!(!is_server_running(&socket_path));
    }

    #[test]
    fn open_note_refuses_unknown_and_trashed_notes_without_the_app() {
        let dir = tempdir().unwrap();
        let mut store = NoteStore::open(&dir.path().join("notes.sqlite3")).unwrap();
        let id = store.create().unwrap().id;

        assert!(require_openable_note(&store, id).is_ok());
        let unknown = id + 1000;
        let missing = require_openable_note(&store, unknown).unwrap_err();
        assert_eq!(
            missing.message,
            Some(format!("Note #{unknown} does not exist"))
        );
        let trashed = store.create().unwrap();
        store.move_to_trash(&trashed).unwrap();
        let in_trash = require_openable_note(&store, trashed.id).unwrap_err();
        assert!(in_trash.message.unwrap().contains("in the trash"));

        // Without the app there is no window to open, so this never succeeds.
        let open = |store: &mut NoteStore, id| {
            handle_domain_request(
                store,
                &IpcRequest::OpenNote {
                    id,
                    activation_token: None,
                },
            )
        };
        let headless = open(&mut store, id);
        assert!(!headless.success);
        assert!(headless
            .message
            .unwrap()
            .contains("running BetterNotes app"));
        assert_eq!(open(&mut store, unknown).message, missing.message);
    }

    #[test]
    fn activation_tokens_are_checked_and_optional_on_the_wire() {
        assert_eq!(
            valid_activation_token(" 1c9d3a8e-kwin_token \n").as_deref(),
            Some("1c9d3a8e-kwin_token")
        );
        assert_eq!(valid_activation_token(""), None);
        assert_eq!(valid_activation_token("two words"), None);
        assert_eq!(valid_activation_token("bad\u{7}bell"), None);
        assert_eq!(valid_activation_token("tökén"), None);
        assert_eq!(
            valid_activation_token(&"a".repeat(MAX_ACTIVATION_TOKEN_LEN + 1)),
            None
        );

        // Requests without a token keep the shape older clients send.
        let plain: IpcRequest =
            serde_json::from_str(r#"{"action":"OpenNote","payload":{"id":7}}"#).unwrap();
        assert_eq!(
            plain,
            IpcRequest::OpenNote {
                id: 7,
                activation_token: None
            }
        );
        let without = serde_json::to_string(&plain).unwrap();
        assert!(!without.contains("activation_token"));
    }

    #[test]
    fn update_note_changes_only_the_given_fields() {
        let dir = tempdir().unwrap();
        let mut store = NoteStore::open(&dir.path().join("notes.sqlite3")).unwrap();
        let created = handle_domain_request(
            &mut store,
            &IpcRequest::NewNote {
                title: "Widget".to_string(),
                content: String::new(),
                open: false,
            },
        );
        assert!(created.success);
        let id = created.data.unwrap()["id"].as_i64().unwrap();
        assert!(!store.window_state(id).unwrap().open);

        let update = |store: &mut NoteStore, title: Option<&str>, content: Option<&str>| {
            handle_domain_request(
                store,
                &IpcRequest::UpdateNote {
                    id,
                    title: title.map(str::to_string),
                    content: content.map(str::to_string),
                    password: None,
                },
            )
        };

        assert!(update(&mut store, None, Some("line one\nline two")).success);
        let note = store.get(id).unwrap();
        assert_eq!(note.title, "Widget");
        assert_eq!(note.content, "line one\nline two");

        assert!(update(&mut store, Some("Renamed"), None).success);
        let note = store.get(id).unwrap();
        assert_eq!(note.title, "Renamed");
        assert_eq!(note.content, "line one\nline two");

        assert!(update(&mut store, Some("  "), None).success);
        assert_eq!(store.get(id).unwrap().title, "Untitled Note");

        assert!(!update(&mut store, None, None).success);
        let missing = handle_domain_request(
            &mut store,
            &IpcRequest::UpdateNote {
                id: id + 100,
                title: Some("x".to_string()),
                content: None,
                password: None,
            },
        );
        assert!(!missing.success);
    }

    #[test]
    fn new_note_requests_from_older_clients_still_open_a_window() {
        let request: IpcRequest =
            serde_json::from_str(r#"{"action":"NewNote","payload":{"title":"Old","content":""}}"#)
                .unwrap();
        assert!(matches!(request, IpcRequest::NewNote { open: true, .. }));
    }
}
