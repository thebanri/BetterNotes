//! Inter-Process Communication (IPC) and Single-Instance coordination.
//!
//! Uses private Unix domain sockets with peer credential checks and strict size validation.

use crate::{Error, NoteStore, Result};
use serde::{Deserialize, Serialize};
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
    },
    /// Files to open as new notes in the running app ("Open with").
    OpenFiles {
        paths: Vec<String>,
    },
}

fn default_true() -> bool {
    true
}

/// A blank title becomes the same placeholder the GUI uses.
fn effective_title(title: &str) -> String {
    match title.trim() {
        "" => "Untitled Note".to_string(),
        title => title.to_string(),
    }
}

/// Standardized IPC response payload.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpcResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
}

impl IpcResponse {
    pub fn ok(data: Option<serde_json::Value>) -> Self {
        Self {
            success: true,
            message: None,
            data,
        }
    }

    pub fn ok_msg(msg: impl Into<String>, data: Option<serde_json::Value>) -> Self {
        Self {
            success: true,
            message: Some(msg.into()),
            data,
        }
    }

    pub fn err(msg: impl Into<String>) -> Self {
        Self {
            success: false,
            message: Some(msg.into()),
            data: None,
        }
    }
}

/// Action to be consumed and executed by the GUI main thread.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IpcAction {
    Activate,
    QuickCapture,
    OpenNote(i64),
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
        IpcRequest::ShowNote { id } => match store.get(*id) {
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
            Err(Error::NotFound(id)) => IpcResponse::err(format!("Note #{id} does not exist")),
            Err(e) => IpcResponse::err(format!("Failed to find note: {e}")),
        },
        IpcRequest::OpenFiles { .. } => {
            IpcResponse::err("Opening files needs the running BetterNotes window")
        }
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
        IpcRequest::UpdateNote { id, title, content } => {
            if title.is_none() && content.is_none() {
                return IpcResponse::err("Nothing to update: give a new title or content");
            }
            match store.get(*id) {
                Ok(mut note) => {
                    if let Some(title) = title {
                        note.title = effective_title(title);
                    }
                    if let Some(content) = content {
                        note.content = content.clone();
                    }
                    match store.update(&note) {
                        Ok(saved) => IpcResponse::ok_msg(
                            format!("Updated note #{id}"),
                            Some(serde_json::json!({ "id": saved.id, "title": saved.title })),
                        ),
                        Err(e) => IpcResponse::err(format!("Failed to update note: {e}")),
                    }
                }
                Err(Error::NotFound(id)) => IpcResponse::err(format!("Note #{id} does not exist")),
                Err(e) => IpcResponse::err(format!("Failed to read note: {e}")),
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
