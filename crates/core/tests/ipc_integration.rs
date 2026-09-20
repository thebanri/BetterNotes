use betternotes_core::{
    handle_domain_request, is_server_running, send_request, IpcAction, IpcRequest, IpcResponse,
    IpcServer, NoteStore, SharedIpcQueue,
};
use std::{
    collections::VecDeque,
    io::Write,
    os::unix::net::UnixStream,
    sync::{Arc, Mutex},
};
use tempfile::tempdir;

#[test]
fn single_instance_detection_and_stale_socket_recovery() {
    let dir = tempdir().unwrap();
    let socket_path = dir.path().join("ipc.sock");

    // Initially no server is running
    assert!(!is_server_running(&socket_path));

    let queue: SharedIpcQueue = Arc::new(Mutex::new(VecDeque::new()));
    let queue_clone = queue.clone();

    // Start server
    let mut server = IpcServer::start(socket_path.clone(), move |req| match req {
        IpcRequest::Ping => IpcResponse::ok_msg("pong", None),
        IpcRequest::Activate => {
            queue_clone.lock().unwrap().push_back(IpcAction::Activate);
            IpcResponse::ok_msg("activated", None)
        }
        _ => IpcResponse::err("unsupported"),
    })
    .unwrap();

    assert!(is_server_running(&socket_path));

    // Send Activate request
    let resp = send_request(&socket_path, &IpcRequest::Activate).unwrap();
    assert!(resp.success);
    assert_eq!(resp.message.as_deref(), Some("activated"));

    // Check queue in GUI
    let action = queue.lock().unwrap().pop_front();
    assert_eq!(action, Some(IpcAction::Activate));

    // Stop server
    server.stop();
    assert!(!is_server_running(&socket_path));
    assert!(!socket_path.exists());

    // Create a dead/stale file at socket_path
    std::fs::write(&socket_path, "dead socket").unwrap();
    assert!(socket_path.exists());
    assert!(!is_server_running(&socket_path));

    // New server should clean up stale file and start cleanly
    let server2 = IpcServer::start(socket_path.clone(), |_| IpcResponse::ok_msg("pong", None));
    assert!(server2.is_ok());
    assert!(is_server_running(&socket_path));
}

#[test]
fn ipc_crud_and_query_dispatch() {
    let dir = tempdir().unwrap();
    let db_path = dir.path().join("test.sqlite3");
    let socket_path = dir.path().join("ipc.sock");

    // Initialize database
    let store_mutex = Arc::new(Mutex::new(NoteStore::open(&db_path).unwrap()));
    let store_clone = store_mutex.clone();

    let server = IpcServer::start(socket_path.clone(), move |req| {
        let mut store = store_clone.lock().unwrap();
        handle_domain_request(&mut store, &req)
    })
    .unwrap();

    // 1. NewNote
    let res = send_request(
        &socket_path,
        &IpcRequest::NewNote {
            title: "Configure nginx".to_string(),
            content: "server { listen 80; }".to_string(),
        },
    )
    .unwrap();
    assert!(res.success);
    let note_id = res.data.unwrap()["id"].as_i64().unwrap();

    // 2. ListNotes
    let list_res = send_request(
        &socket_path,
        &IpcRequest::ListNotes {
            include_archived: false,
        },
    )
    .unwrap();
    assert!(list_res.success);
    let notes = list_res.data.unwrap();
    assert_eq!(notes.as_array().unwrap().len(), 1);
    assert_eq!(notes[0]["id"].as_i64().unwrap(), note_id);
    assert_eq!(notes[0]["title"].as_str().unwrap(), "Configure nginx");

    // 3. SearchNotes
    let search_res = send_request(
        &socket_path,
        &IpcRequest::SearchNotes {
            query: "nginx".to_string(),
        },
    )
    .unwrap();
    assert!(search_res.success);
    let search_hits = search_res.data.unwrap();
    assert_eq!(search_hits.as_array().unwrap().len(), 1);
    assert_eq!(search_hits[0]["id"].as_i64().unwrap(), note_id);

    // 4. ShowNote
    let show_res = send_request(&socket_path, &IpcRequest::ShowNote { id: note_id }).unwrap();
    assert!(show_res.success);
    let note = show_res.data.unwrap();
    assert_eq!(note["content"].as_str().unwrap(), "server { listen 80; }");

    // 5. ArchiveNote
    let arch_res = send_request(
        &socket_path,
        &IpcRequest::ArchiveNote {
            id: note_id,
            archived: true,
        },
    )
    .unwrap();
    assert!(arch_res.success);

    // Verify ListNotes without archived excludes it
    let list_active = send_request(
        &socket_path,
        &IpcRequest::ListNotes {
            include_archived: false,
        },
    )
    .unwrap();
    assert_eq!(list_active.data.unwrap().as_array().unwrap().len(), 0);

    // Verify ListNotes with archived includes it
    let list_archived = send_request(
        &socket_path,
        &IpcRequest::ListNotes {
            include_archived: true,
        },
    )
    .unwrap();
    assert_eq!(list_archived.data.unwrap().as_array().unwrap().len(), 1);

    drop(server);
}

#[test]
fn ipc_untrusted_input_and_size_limits() {
    let dir = tempdir().unwrap();
    let socket_path = dir.path().join("ipc.sock");

    let _server = IpcServer::start(socket_path.clone(), |_| {
        IpcResponse::ok_msg("processed", None)
    })
    .unwrap();

    // 1. Send invalid JSON
    let mut stream = UnixStream::connect(&socket_path).unwrap();
    stream.write_all(b"NOT VALID JSON\n").unwrap();
    stream.flush().unwrap();

    let mut reader = std::io::BufReader::new(stream);
    let mut line = String::new();
    std::io::BufRead::read_line(&mut reader, &mut line).unwrap();
    let res: IpcResponse = serde_json::from_str(&line).unwrap();
    assert!(!res.success);
    assert!(res.message.unwrap().contains("Invalid request JSON"));

    // 2. Headless store handling behaves identically
    let db_path = dir.path().join("headless.sqlite3");
    let mut store = NoteStore::open(&db_path).unwrap();
    let direct_res = handle_domain_request(
        &mut store,
        &IpcRequest::NewNote {
            title: "Headless Note".to_string(),
            content: "Created without running GUI".to_string(),
        },
    );
    assert!(direct_res.success);
    assert_eq!(
        direct_res.data.unwrap()["title"].as_str(),
        Some("Headless Note")
    );
}
