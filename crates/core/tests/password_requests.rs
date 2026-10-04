use betternotes_core::{
    handle_domain_request, send_request, vault, IpcErrorKind, IpcRequest, IpcResponse, IpcServer,
    NoteStore, NotesSession, Password,
};

fn show(store: &mut NoteStore, id: i64, password: Option<&str>) -> IpcResponse {
    handle_domain_request(
        store,
        &IpcRequest::ShowNote {
            id,
            password: password.map(|p| Password::new(p.to_string())),
        },
    )
}

fn update_content(
    store: &mut NoteStore,
    id: i64,
    content: &str,
    password: Option<&str>,
) -> IpcResponse {
    handle_domain_request(
        store,
        &IpcRequest::UpdateNote {
            id,
            title: None,
            content: Some(content.to_string()),
            password: password.map(|p| Password::new(p.to_string())),
        },
    )
}

fn content_of(response: &IpcResponse) -> &str {
    response.data.as_ref().unwrap()["content"].as_str().unwrap()
}

// One test: the unlocked key is process-wide, and this file's own binary keeps
// the vault test from changing it underneath.
#[test]
fn show_and_update_take_a_password_for_one_request() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("notes.sqlite3");
    let mut session = NotesSession::open(&path).unwrap();
    session.create().unwrap();
    session.edit_title("Bank".into());
    session.edit_content("PIN 4821".into());
    session.save().unwrap();
    let locked_id = session.current().unwrap().id;
    vault::set_up(session.store(), "correct horse").unwrap();
    session.set_locked(true).unwrap();
    session.create().unwrap();
    session.edit_content("plain".into());
    session.save().unwrap();
    let plain_id = session.current().unwrap().id;
    drop(session);
    vault::lock();
    let mut store = NoteStore::open(&path).unwrap();

    // Without a password the caller learns the note is locked.
    let response = show(&mut store, locked_id, None);
    assert!(!response.success);
    assert_eq!(response.error, Some(IpcErrorKind::Locked));
    let response = update_content(&mut store, locked_id, "x", None);
    assert_eq!(response.error, Some(IpcErrorKind::Locked));

    // A wrong password is told apart from a missing note.
    let response = show(&mut store, locked_id, Some("wrong password"));
    assert_eq!(response.error, Some(IpcErrorKind::WrongPassword));
    let response = update_content(&mut store, locked_id, "x", Some("wrong password"));
    assert_eq!(response.error, Some(IpcErrorKind::WrongPassword));
    let response = show(&mut store, locked_id + 100, Some("correct horse"));
    assert!(!response.success);
    assert_eq!(response.error, None);
    assert!(response.message.unwrap().contains("does not exist"));

    // The right password reads and writes, and stays with the request.
    let response = show(&mut store, locked_id, Some("correct horse"));
    assert!(response.success);
    assert_eq!(content_of(&response), "PIN 4821");
    assert!(!vault::is_unlocked());
    let response = update_content(&mut store, locked_id, "PIN 9157", Some("correct horse"));
    assert!(response.success, "{:?}", response.message);
    assert!(!vault::is_unlocked());
    let raw: String = store
        .raw_connection()
        .query_row(
            "SELECT content FROM notes WHERE id = ?1",
            [locked_id],
            |row| row.get(0),
        )
        .unwrap();
    assert!(raw.starts_with(vault::SEALED_PREFIX) && !raw.contains("9157"));
    assert!(store.search("9157").unwrap().is_empty());
    let response = show(&mut store, locked_id, Some("correct horse"));
    assert_eq!(content_of(&response), "PIN 9157");

    // A password is checked even while the app is unlocked.
    assert!(vault::unlock(&store, "correct horse").unwrap());
    let response = show(&mut store, locked_id, Some("wrong password"));
    assert_eq!(response.error, Some(IpcErrorKind::WrongPassword));
    vault::lock();

    // Notes that are not locked ignore it.
    let response = show(&mut store, plain_id, Some("anything"));
    assert_eq!(content_of(&response), "plain");
    assert!(update_content(&mut store, plain_id, "changed", Some("anything")).success);
    assert_eq!(store.get(plain_id).unwrap().content, "changed");

    // Through a running app's socket, the password and the error kind
    // arrive as they do headless.
    let socket_path = directory.path().join("ipc.sock");
    let server_db = path.clone();
    let _server = IpcServer::start(socket_path.clone(), move |request| {
        handle_domain_request(&mut NoteStore::open(&server_db).unwrap(), &request)
    })
    .unwrap();
    let send = |password: Option<&str>| {
        send_request(
            &socket_path,
            &IpcRequest::ShowNote {
                id: locked_id,
                password: password.map(|p| Password::new(p.to_string())),
            },
        )
        .unwrap()
    };
    assert_eq!(send(None).error, Some(IpcErrorKind::Locked));
    assert_eq!(
        send(Some("wrong password")).error,
        Some(IpcErrorKind::WrongPassword)
    );
    assert_eq!(content_of(&send(Some("correct horse"))), "PIN 9157");
    assert!(!vault::is_unlocked());
}

#[test]
fn passwords_stay_out_of_debug_output_and_old_messages_still_parse() {
    let request = IpcRequest::ShowNote {
        id: 4,
        password: Some(Password::new("hunter2 hunter2".to_string())),
    };
    assert!(!format!("{request:?}").contains("hunter2"));
    let wire = serde_json::to_string(&request).unwrap();
    assert_eq!(serde_json::from_str::<IpcRequest>(&wire).unwrap(), request);

    // Requests and responses without the new fields, as older versions send.
    let old: IpcRequest =
        serde_json::from_str(r#"{"action":"ShowNote","payload":{"id":4}}"#).unwrap();
    assert_eq!(
        old,
        IpcRequest::ShowNote {
            id: 4,
            password: None
        }
    );
    let response: IpcResponse =
        serde_json::from_str(r#"{"success":false,"message":"locked"}"#).unwrap();
    assert_eq!(response.error, None);
    let wrong = serde_json::to_string(&IpcResponse::err_kind(
        IpcErrorKind::WrongPassword,
        "The password is wrong",
    ))
    .unwrap();
    assert!(wrong.contains(r#""error":"wrong_password""#));
}
