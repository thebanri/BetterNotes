//! Locked notes: one master password protects the content of every note the
//! user locks.
//!
//! The password is stretched with Argon2id into a 256-bit key, and each
//! locked note's content is sealed with XChaCha20-Poly1305 under a random
//! nonce. The key lives only in this process's memory, from unlocking until
//! locking or quitting; the password is never stored. A known value sealed
//! with the key lets a password be checked. Without the password, locked
//! content cannot be recovered.

use crate::{Error, NoteStore, Result};
use argon2::{Algorithm, Argon2, Params, Version};
use chacha20poly1305::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    XChaCha20Poly1305, XNonce,
};
use std::sync::Mutex;
use zeroize::Zeroizing;

/// Marks stored content as sealed, and names the format.
pub const SEALED_PREFIX: &str = "bnenc1:";
const SALT_KEY: &str = "vault_salt";
const CHECK_KEY: &str = "vault_check";
const CHECK_VALUE: &[u8] = b"BetterNotes vault v1";
const SALT_BYTES: usize = 16;
const NONCE_BYTES: usize = 24;
/// Shortest master password accepted.
pub const MIN_PASSWORD_CHARS: usize = 8;

type Key = Zeroizing<[u8; 32]>;

/// The unlocked key, shared by every window of this process.
static KEY: Mutex<Option<Key>> = Mutex::new(None);

fn invalid(message: &str) -> Error {
    Error::Io(std::io::Error::new(
        std::io::ErrorKind::InvalidInput,
        message.to_string(),
    ))
}

fn derive(password: &str, salt: &[u8]) -> Result<Key> {
    // OWASP's Argon2id minimum: 19 MiB, 2 passes, 1 lane.
    let params = Params::new(19 * 1024, 2, 1, Some(32)).map_err(|e| invalid(&e.to_string()))?;
    let mut key = Zeroizing::new([0u8; 32]);
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
        .hash_password_into(password.as_bytes(), salt, key.as_mut())
        .map_err(|e| invalid(&e.to_string()))?;
    Ok(key)
}

fn seal_with(key: &Key, plain: &[u8]) -> Result<String> {
    let cipher = XChaCha20Poly1305::new(key.as_ref().into());
    let nonce = XChaCha20Poly1305::generate_nonce(&mut OsRng);
    let sealed = cipher
        .encrypt(&nonce, plain)
        .map_err(|_| invalid("Could not encrypt the note"))?;
    let mut bytes = nonce.to_vec();
    bytes.extend_from_slice(&sealed);
    Ok(format!("{SEALED_PREFIX}{}", to_hex(&bytes)))
}

fn open_with(key: &Key, sealed: &str) -> Result<Vec<u8>> {
    let bytes = sealed
        .strip_prefix(SEALED_PREFIX)
        .and_then(from_hex)
        .filter(|bytes| bytes.len() > NONCE_BYTES)
        .ok_or_else(|| invalid("The locked note is damaged"))?;
    let (nonce, ciphertext) = bytes.split_at(NONCE_BYTES);
    XChaCha20Poly1305::new(key.as_ref().into())
        .decrypt(XNonce::from_slice(nonce), ciphertext)
        .map_err(|_| Error::Locked)
}

/// Whether a master password has been set.
pub fn is_set(store: &NoteStore) -> Result<bool> {
    Ok(store
        .get_setting(CHECK_KEY)?
        .is_some_and(|check| !check.is_empty()))
}

pub fn is_unlocked() -> bool {
    KEY.lock().map(|key| key.is_some()).unwrap_or(false)
}

/// Sets the master password the first time, and unlocks.
pub fn set_up(store: &NoteStore, password: &str) -> Result<()> {
    if is_set(store)? {
        return Err(invalid("A password is already set; change it instead"));
    }
    if password.chars().count() < MIN_PASSWORD_CHARS {
        return Err(invalid("Use at least 8 characters"));
    }
    let salt: [u8; SALT_BYTES] = random();
    let key = derive(password, &salt)?;
    let check = seal_with(&key, CHECK_VALUE)?;
    store.set_setting(SALT_KEY, &to_hex(&salt))?;
    store.set_setting(CHECK_KEY, &check)?;
    *KEY.lock().map_err(|_| Error::Locked)? = Some(key);
    Ok(())
}

/// Unlocks with the master password; false when it is wrong.
pub fn unlock(store: &NoteStore, password: &str) -> Result<bool> {
    let (Some(salt), Some(check)) = (store.get_setting(SALT_KEY)?, store.get_setting(CHECK_KEY)?)
    else {
        return Err(invalid("No password is set"));
    };
    let salt = from_hex(&salt).ok_or_else(|| invalid("The password settings are damaged"))?;
    let key = derive(password, &salt)?;
    match open_with(&key, &check) {
        Ok(value) if value == CHECK_VALUE => {
            *KEY.lock().map_err(|_| Error::Locked)? = Some(key);
            Ok(true)
        }
        Ok(_) | Err(Error::Locked) => Ok(false),
        Err(error) => Err(error),
    }
}

/// Forgets the key; locked notes cannot be read until unlocked again.
pub fn lock() {
    if let Ok(mut key) = KEY.lock() {
        *key = None;
    }
}

/// Seals note content with the unlocked key.
pub fn seal(plain: &str) -> Result<String> {
    let guard = KEY.lock().map_err(|_| Error::Locked)?;
    let key = guard.as_ref().ok_or(Error::Locked)?;
    seal_with(key, plain.as_bytes())
}

/// Opens sealed content with the unlocked key.
pub fn open(sealed: &str) -> Result<String> {
    let guard = KEY.lock().map_err(|_| Error::Locked)?;
    let key = guard.as_ref().ok_or(Error::Locked)?;
    String::from_utf8(open_with(key, sealed)?).map_err(|_| invalid("The locked note is damaged"))
}

/// Changes the master password: every locked note is resealed with the new
/// key in one transaction, so a failure leaves all of them as they were.
pub fn change_password(store: &NoteStore, current: &str, new: &str) -> Result<()> {
    if new.chars().count() < MIN_PASSWORD_CHARS {
        return Err(invalid("Use at least 8 characters"));
    }
    if !unlock(store, current)? {
        return Err(invalid("The current password is wrong"));
    }
    let salt: [u8; SALT_BYTES] = random();
    let new_key = derive(new, &salt)?;
    let connection = store.raw_connection();
    connection.execute_batch("BEGIN IMMEDIATE")?;
    let result = (|| -> Result<()> {
        let sealed: Vec<(i64, String)> = {
            let mut statement =
                connection.prepare("SELECT id, content FROM notes WHERE is_locked = 1")?;
            let rows = statement.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?;
            rows.collect::<rusqlite::Result<_>>()?
        };
        for (id, content) in sealed {
            let plain = Zeroizing::new(open(&content)?);
            connection.execute(
                "UPDATE notes SET content = ?1 WHERE id = ?2",
                rusqlite::params![seal_with(&new_key, plain.as_bytes())?, id],
            )?;
        }
        store.set_setting(SALT_KEY, &to_hex(&salt))?;
        store.set_setting(CHECK_KEY, &seal_with(&new_key, CHECK_VALUE)?)?;
        Ok(())
    })();
    match result {
        Ok(()) => {
            connection.execute_batch("COMMIT")?;
            *KEY.lock().map_err(|_| Error::Locked)? = Some(new_key);
            Ok(())
        }
        Err(error) => {
            let _ = connection.execute_batch("ROLLBACK");
            Err(error)
        }
    }
}

fn random<const N: usize>() -> [u8; N] {
    use chacha20poly1305::aead::rand_core::RngCore;
    let mut bytes = [0u8; N];
    OsRng.fill_bytes(&mut bytes);
    bytes
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn from_hex(text: &str) -> Option<Vec<u8>> {
    if !text.len().is_multiple_of(2) {
        return None;
    }
    (0..text.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(text.get(i..i + 2)?, 16).ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sealed_content_needs_the_right_key() {
        let key: Key = Zeroizing::new([7; 32]);
        let other: Key = Zeroizing::new([8; 32]);
        let sealed = seal_with(&key, "gizli not".as_bytes()).unwrap();
        assert!(sealed.starts_with(SEALED_PREFIX));
        assert!(!sealed.contains("gizli"));
        assert_ne!(
            sealed,
            seal_with(&key, "gizli not".as_bytes()).unwrap(),
            "nonces must differ"
        );
        assert_eq!(open_with(&key, &sealed).unwrap(), "gizli not".as_bytes());
        assert!(matches!(open_with(&other, &sealed), Err(Error::Locked)));
        let mut tampered = sealed.clone();
        tampered.pop();
        tampered.push('0');
        assert!(open_with(&key, &tampered).is_err());
        assert!(open_with(&key, "bnenc1:zz").is_err());
        assert_eq!(from_hex(&to_hex(&[0, 255, 16])).unwrap(), [0, 255, 16]);
    }
}
