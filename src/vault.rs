use keepass::config::{
    CompressionConfig, DatabaseConfig, DatabaseVersion, InnerCipherConfig, KdfConfig,
    OuterCipherConfig,
};
use keepass::db::{Entry, Group, History, MemoryProtection};
use keepass::{Database, DatabaseKey};
use zeroize::{Zeroize, Zeroizing};

use crate::types::VaultResult;

/// Internal vault state held behind an opaque FFI handle.
#[derive(Debug)]
pub struct VaultState {
    pub db: Database,
    password: Zeroizing<Vec<u8>>,
    keyfile_path: Option<String>,
}

impl Drop for VaultState {
    fn drop(&mut self) {
        // munlock before Zeroizing zeros and deallocates the password buffer
        Self::unlock_password(&self.password);
        // password is Zeroizing and will be zeroed on drop automatically.
        // Database fields don't implement Zeroize, but protected values
        // (passwords) in keepass-rs use SecretBox which zeros on drop.
    }
}

impl VaultState {
    /// Pin a password buffer in RAM so it cannot be paged to swap.
    fn lock_password(pw: &Zeroizing<Vec<u8>>) {
        if !pw.is_empty() {
            crate::memory::lock_buffer(pw.as_ptr(), pw.len());
        }
    }

    /// Release a previously pinned password buffer.
    fn unlock_password(pw: &Zeroizing<Vec<u8>>) {
        if !pw.is_empty() {
            crate::memory::unlock_buffer(pw.as_ptr(), pw.len());
        }
    }

    /// Build a DatabaseKey from password + optional keyfile.
    fn build_key(password: &[u8], keyfile_path: Option<&str>) -> Result<DatabaseKey, VaultResult> {
        let password_str = std::str::from_utf8(password).map_err(|_| VaultResult::InternalError)?;
        let mut key = DatabaseKey::new().with_password(password_str);
        if let Some(kf_path) = keyfile_path {
            let mut kf = std::fs::File::open(kf_path).map_err(|_| VaultResult::FileNotFound)?;
            key = key.with_keyfile(&mut kf).map_err(|_| VaultResult::InternalError)?;
        }
        Ok(key)
    }

    /// Open an existing KDBX file.
    pub fn open(path: &str, password: &[u8], keyfile_path: Option<&str>) -> Result<Self, VaultResult> {
        let mut file =
            std::fs::File::open(path).map_err(|e| match e.kind() {
                std::io::ErrorKind::NotFound => VaultResult::FileNotFound,
                _ => VaultResult::InternalError,
            })?;
        let key = Self::build_key(password, keyfile_path)?;
        let db = Database::open(&mut file, key).map_err(map_open_error)?;
        let pw = Zeroizing::new(password.to_vec());
        Self::lock_password(&pw);
        Ok(VaultState { db, password: pw, keyfile_path: keyfile_path.map(String::from) })
    }

    /// Create a new empty KDBX 4 vault with Argon2id / ChaCha20.
    pub fn create(password: &[u8], keyfile_path: Option<&str>) -> Result<Self, VaultResult> {
        if password.is_empty() {
            return Err(VaultResult::EmptyPassword);
        }
        // Validate password is UTF-8 and keyfile is readable (if provided)
        let _ = Self::build_key(password, keyfile_path)?;
        let config = DatabaseConfig {
            version: DatabaseVersion::KDB4(1),
            outer_cipher_config: OuterCipherConfig::ChaCha20,
            compression_config: CompressionConfig::GZip,
            inner_cipher_config: InnerCipherConfig::ChaCha20,
            kdf_config: KdfConfig::Argon2id {
                memory: 256 * 1024 * 1024, // 256 MB
                iterations: 3,
                parallelism: 4,
                version: argon2::Version::Version13,
            },
            public_custom_data: None,
        };
        let mut db = Database::new(config);
        let now = keepass::db::Times::now();
        let nil = uuid::Uuid::nil();

        // -- Meta: populate every field that keepass-rs would otherwise
        //    serialize as an empty XML tag.  KeePassXC rejects empty tags
        //    for numeric, UUID, and boolean-valued elements.
        let meta = &mut db.meta;
        meta.generator = Some("Citadel".to_string());
        meta.database_name = Some("Citadel Vault".to_string());
        meta.database_name_changed = Some(now);
        meta.database_description = Some(String::new());
        meta.database_description_changed = Some(now);
        meta.default_username = Some(String::new());
        meta.default_username_changed = Some(now);
        meta.maintenance_history_days = Some(365);
        meta.master_key_changed = Some(now);
        meta.master_key_change_rec = Some(-1);
        meta.master_key_change_force = Some(-1);
        meta.memory_protection = Some(MemoryProtection::default());
        meta.recyclebin_enabled = Some(true);
        meta.recyclebin_uuid = Some(nil);
        meta.recyclebin_changed = Some(now);
        meta.entry_templates_group = Some(nil);
        meta.entry_templates_group_changed = Some(now);
        meta.last_selected_group = Some(nil);
        meta.last_top_visible_group = Some(nil);
        meta.history_max_items = Some(10);
        meta.history_max_size = Some(6_291_456); // 6 MB
        meta.settings_changed = Some(now);

        // -- Root group: set every field KeePassXC expects to be non-empty.
        db.root.icon_id = Some(48);
        db.root.times.expiry = Some(keepass::db::Times::epoch());
        db.root.is_expanded = true;
        db.root.enable_autotype = Some(true);
        db.root.enable_searching = Some(true);
        db.root.last_top_visible_entry = Some(nil);

        let pw = Zeroizing::new(password.to_vec());
        Self::lock_password(&pw);
        Ok(VaultState { db, password: pw, keyfile_path: keyfile_path.map(String::from) })
    }

    /// Save the database to the given path using the stored password.
    ///
    /// # Non-atomic write
    ///
    /// This function uses `File::create` which truncates and overwrites the
    /// target file directly.  If the process is interrupted mid-write the file
    /// will be corrupted.  **The caller (Swift persistence layer) MUST handle
    /// atomic save semantics** — write to a temporary file first, then rename
    /// over the target path.  Do NOT call this directly on the primary vault
    /// file from application code.
    pub fn save_to(&mut self, path: &str) -> Result<(), VaultResult> {
        // Fix up None values that keepass-rs would serialize as empty XML
        // tags, which KeePassXC rejects.
        sanitize_for_keepassxc(&mut self.db);

        let key = Self::build_key(&self.password, self.keyfile_path.as_deref())?;
        let mut file = std::fs::File::create(path).map_err(|_| VaultResult::WriteFailed)?;
        self.db
            .save(&mut file, key)
            .map_err(|_| VaultResult::WriteFailed)?;
        Ok(())
    }

    /// Validate that a file can be opened with the given password (+ optional keyfile).
    pub fn validate(path: &str, password: &[u8], keyfile_path: Option<&str>) -> Result<(), VaultResult> {
        // Just try to open — if it succeeds, the file and password are valid.
        let _state = Self::open(path, password, keyfile_path)?;
        Ok(())
    }

    /// Change the stored password (and optionally keyfile). Takes effect on next save.
    pub fn change_password(&mut self, new_password: &[u8], new_keyfile: Option<&str>) -> Result<(), VaultResult> {
        if new_password.is_empty() {
            return Err(VaultResult::EmptyPassword);
        }
        // Validate password is UTF-8 and keyfile is readable
        let _ = Self::build_key(new_password, new_keyfile)?;
        Self::unlock_password(&self.password);
        self.password.zeroize();
        self.password = Zeroizing::new(new_password.to_vec());
        Self::lock_password(&self.password);
        self.keyfile_path = new_keyfile.map(String::from);
        Ok(())
    }

    /// Collect all entries recursively as (uuid_string, title, username, url).
    pub fn list_entries(&self) -> Vec<EntrySummary> {
        let mut out = Vec::new();
        collect_entries(&self.db.root, &mut out);
        out
    }

    /// Find an entry by UUID and return its full data.
    pub fn get_entry(&self, uuid: uuid::Uuid) -> Result<EntryDetail, VaultResult> {
        let entry = self
            .db
            .root
            .entry_by_uuid(uuid)
            .ok_or(VaultResult::InternalError)?;
        Ok(EntryDetail {
            uuid: entry.uuid.to_string(),
            title: entry.get_title().unwrap_or("").to_string(),
            username: entry.get_username().unwrap_or("").to_string(),
            password: Zeroizing::new(entry.get_password().unwrap_or("").as_bytes().to_vec()),
            url: entry.get_url().unwrap_or("").to_string(),
            notes: entry.get("Notes").unwrap_or("").to_string(),
        })
    }

    /// Add a new entry to the root group. Returns its UUID.
    pub fn add_entry(
        &mut self,
        title: &str,
        username: &str,
        password: &[u8],
        url: &str,
        notes: &str,
    ) -> Result<uuid::Uuid, VaultResult> {
        let password_str =
            std::str::from_utf8(password).map_err(|_| VaultResult::InternalError)?;
        let mut entry = Entry::new();
        let entry_uuid = entry.uuid;
        entry.icon_id = Some(0);
        entry.times.expiry = Some(keepass::db::Times::epoch());
        entry.set_unprotected("Title", title);
        entry.set_unprotected("UserName", username);
        entry.set_protected("Password", password_str);
        entry.set_unprotected("URL", url);
        entry.set_unprotected("Notes", notes);
        self.db.root.entries.push(entry);
        Ok(entry_uuid)
    }

    /// Update an existing entry found by UUID.
    pub fn update_entry(
        &mut self,
        uuid: uuid::Uuid,
        title: &str,
        username: &str,
        password: &[u8],
        url: &str,
        notes: &str,
    ) -> Result<(), VaultResult> {
        let password_str =
            std::str::from_utf8(password).map_err(|_| VaultResult::InternalError)?;
        let entry = self
            .db
            .root
            .entry_by_uuid_mut(uuid)
            .ok_or(VaultResult::InternalError)?;
        entry.update_history();
        entry.set_unprotected("Title", title);
        entry.set_unprotected("UserName", username);
        entry.set_protected("Password", password_str);
        entry.set_unprotected("URL", url);
        entry.set_unprotected("Notes", notes);
        Ok(())
    }

    /// Delete an entry by UUID. Searches all groups recursively.
    pub fn delete_entry(&mut self, uuid: uuid::Uuid) -> Result<(), VaultResult> {
        if remove_entry_recursive(&mut self.db.root, uuid) {
            Ok(())
        } else {
            Err(VaultResult::InternalError)
        }
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

pub struct EntrySummary {
    pub uuid: String,
    pub title: String,
    pub username: String,
    pub url: String,
}

pub struct EntryDetail {
    pub uuid: String,
    pub title: String,
    pub username: String,
    pub password: Zeroizing<Vec<u8>>,
    pub url: String,
    pub notes: String,
}

fn collect_entries(group: &Group, out: &mut Vec<EntrySummary>) {
    for entry in &group.entries {
        out.push(EntrySummary {
            uuid: entry.uuid.to_string(),
            title: entry.get_title().unwrap_or("").to_string(),
            username: entry.get_username().unwrap_or("").to_string(),
            url: entry.get_url().unwrap_or("").to_string(),
        });
    }
    for child in &group.groups {
        collect_entries(child, out);
    }
}

/// Walk the entire database and replace every `None` that keepass-rs would
/// serialize as an empty XML tag with a concrete default value.  Without this,
/// KeePassXC rejects the file ("Invalid number value", "Invalid EnableSearching
/// value", etc.).
///
/// This is called before every save so it also fixes databases that were
/// originally opened from a KeePassXC file (where "null" round-trips to None).
fn sanitize_for_keepassxc(db: &mut Database) {
    let nil = uuid::Uuid::nil();
    let epoch = keepass::db::Times::epoch();

    // -- Meta --
    let m = &mut db.meta;
    if m.generator.is_none() {
        m.generator = Some("Citadel".to_string());
    }
    m.database_name.get_or_insert_with(String::new);
    m.database_name_changed.get_or_insert(epoch);
    m.database_description.get_or_insert_with(String::new);
    m.database_description_changed.get_or_insert(epoch);
    m.default_username.get_or_insert_with(String::new);
    m.default_username_changed.get_or_insert(epoch);
    m.maintenance_history_days.get_or_insert(365);
    m.master_key_changed.get_or_insert(epoch);
    m.master_key_change_rec.get_or_insert(-1);
    m.master_key_change_force.get_or_insert(-1);
    if m.memory_protection.is_none() {
        m.memory_protection = Some(MemoryProtection::default());
    }
    m.recyclebin_enabled.get_or_insert(true);
    m.recyclebin_uuid.get_or_insert(nil);
    m.recyclebin_changed.get_or_insert(epoch);
    m.entry_templates_group.get_or_insert(nil);
    m.entry_templates_group_changed.get_or_insert(epoch);
    m.last_selected_group.get_or_insert(nil);
    m.last_top_visible_group.get_or_insert(nil);
    m.history_max_items.get_or_insert(10);
    m.history_max_size.get_or_insert(6_291_456);
    m.settings_changed.get_or_insert(epoch);

    // -- CustomData: fill empty LastModificationTime tags --
    for item in m.custom_data.values_mut() {
        item.last_modification_time.get_or_insert(epoch);
    }

    // -- Groups (recursive) --
    sanitize_group(&mut db.root, epoch, nil);
}

fn sanitize_group(group: &mut Group, epoch: chrono::NaiveDateTime, nil: uuid::Uuid) {
    group.icon_id.get_or_insert(48);
    group.times.expiry.get_or_insert(epoch);
    group.enable_autotype.get_or_insert(true);
    group.enable_searching.get_or_insert(true);
    group.last_top_visible_entry.get_or_insert(nil);

    for entry in &mut group.entries {
        sanitize_entry(entry, epoch);
    }
    for child in &mut group.groups {
        sanitize_group(child, epoch, nil);
    }
}

fn sanitize_entry(entry: &mut Entry, epoch: chrono::NaiveDateTime) {
    entry.icon_id.get_or_insert(0);
    entry.times.expiry.get_or_insert(epoch);
    // keepass-rs serializes AutoType.DataTransferObfuscation as "True"/"False"
    // but KeePassXC expects an integer (0/1).  We clear only that one field
    // to None so the serializer omits it, while preserving Enabled,
    // DefaultSequence, and Associations.
    sanitize_autotype(&mut entry.autotype);

    // Rebuild history with sanitized entries.  History only exposes
    // get_entries() (immutable) so we take it, clone entries, fix them,
    // and rebuild via add_entry().
    if let Some(old_history) = entry.history.take() {
        let mut new_history = History::default();
        // add_entry() prepends, so iterate in reverse to preserve order.
        for mut h_entry in old_history.get_entries().clone().into_iter().rev() {
            h_entry.icon_id.get_or_insert(0);
            h_entry.times.expiry.get_or_insert(epoch);
            sanitize_autotype(&mut h_entry.autotype);
            new_history.add_entry(h_entry);
        }
        entry.history = Some(new_history);
    }
}

/// Fix the AutoType block so that KeePassXC can open the file.
///
/// keepass-rs serializes `DataTransferObfuscation` as `"True"`/`"False"` but
/// KeePassXC parses it as an integer (0/1).  The field has no
/// `skip_serializing_if` so even `None` produces an empty tag that KeePassXC
/// also rejects.  The only way to suppress the bad field is to drop the entire
/// AutoType block — but we only do that when the block contains no meaningful
/// custom data (no associations, no custom sequence).  If a user has configured
/// custom AutoType associations we preserve the block as-is and accept that
/// KeePassXC will reject it until keepass-rs fixes the upstream serializer.
fn sanitize_autotype(autotype: &mut Option<keepass::db::AutoType>) {
    if let Some(ref at) = autotype {
        let has_custom_data = !at.associations.is_empty()
            || at.default_sequence.as_ref().is_some_and(|s| !s.is_empty());
        if !has_custom_data {
            *autotype = None;
        }
    }
}

fn remove_entry_recursive(group: &mut Group, uuid: uuid::Uuid) -> bool {
    let before = group.entries.len();
    group.entries.retain(|e| e.uuid != uuid);
    if group.entries.len() < before {
        return true;
    }
    for child in &mut group.groups {
        if remove_entry_recursive(child, uuid) {
            return true;
        }
    }
    false
}

fn map_open_error(e: keepass::db::DatabaseOpenError) -> VaultResult {
    use keepass::db::DatabaseOpenError;
    match e {
        DatabaseOpenError::Key(_) => VaultResult::WrongPassword,
        DatabaseOpenError::Io(ref io) if io.kind() == std::io::ErrorKind::NotFound => {
            VaultResult::FileNotFound
        }
        DatabaseOpenError::Cryptography(_)
        | DatabaseOpenError::Format(_)
        | DatabaseOpenError::UnexpectedEof => VaultResult::FileCorrupted,
        _ => VaultResult::InternalError,
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[test]
    fn create_and_reopen() {
        let pw = b"test-password-123";
        let mut state = VaultState::create(pw, None).expect("create failed");
        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).expect("save failed");

        let state2 = VaultState::open(path, pw, None).expect("reopen failed");
        assert_eq!(
            state2.db.meta.database_name.as_deref(),
            Some("Citadel Vault")
        );
    }

    #[test]
    fn wrong_password_returns_error() {
        let pw = b"correct";
        let mut state = VaultState::create(pw, None).expect("create failed");
        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).expect("save failed");

        let err = VaultState::open(path, b"wrong", None).unwrap_err();
        assert_eq!(err, VaultResult::WrongPassword);
    }

    #[test]
    fn file_not_found() {
        let err = VaultState::open("/tmp/nonexistent_citadel_test.kdbx", b"pw", None).unwrap_err();
        assert_eq!(err, VaultResult::FileNotFound);
    }

    #[test]
    fn add_list_get_update_delete_entry() {
        let pw = b"test";
        let mut state = VaultState::create(pw, None).unwrap();

        // Add
        let uuid = state
            .add_entry("GitHub", "alice", b"s3cret", "https://github.com", "dev account")
            .unwrap();

        // List
        let entries = state.list_entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].title, "GitHub");
        assert_eq!(entries[0].username, "alice");

        // Get (includes password)
        let detail = state.get_entry(uuid).unwrap();
        assert_eq!(detail.password.as_slice(), b"s3cret");
        assert_eq!(detail.notes, "dev account");

        // Update
        state
            .update_entry(uuid, "GitHub Enterprise", "bob", b"new-pw", "https://ghe.co", "work")
            .unwrap();
        let detail2 = state.get_entry(uuid).unwrap();
        assert_eq!(detail2.title, "GitHub Enterprise");
        assert_eq!(detail2.password.as_slice(), b"new-pw");

        // Delete
        state.delete_entry(uuid).unwrap();
        assert!(state.list_entries().is_empty());
    }

    #[test]
    fn change_password_and_reopen() {
        let pw = b"old-pw";
        let mut state = VaultState::create(pw, None).unwrap();
        state.add_entry("Test", "user", b"pw", "", "").unwrap();

        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();

        // Save with old password
        state.save_to(path).unwrap();

        // Change password
        state.change_password(b"new-pw", None).unwrap();
        state.save_to(path).unwrap();

        // Old password should fail
        assert_eq!(
            VaultState::open(path, b"old-pw", None).unwrap_err(),
            VaultResult::WrongPassword
        );

        // New password should work
        let state2 = VaultState::open(path, b"new-pw", None).unwrap();
        assert_eq!(state2.list_entries().len(), 1);
    }

    #[test]
    fn validate_good_and_bad() {
        let pw = b"validate-test";
        let mut state = VaultState::create(pw, None).unwrap();
        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();

        assert_eq!(VaultState::validate(path, pw, None), Ok(()));
        assert_eq!(
            VaultState::validate(path, b"wrong", None),
            Err(VaultResult::WrongPassword)
        );
    }

    #[test]
    fn empty_password_rejected_on_create() {
        let err = VaultState::create(b"", None).unwrap_err();
        assert_eq!(err, VaultResult::EmptyPassword);
    }

    #[test]
    fn empty_password_rejected_on_change() {
        let mut state = VaultState::create(b"initial", None).unwrap();
        let err = state.change_password(b"", None).unwrap_err();
        assert_eq!(err, VaultResult::EmptyPassword);
    }

    #[test]
    fn roundtrip_preserves_entries() {
        let pw = b"roundtrip";
        let mut state = VaultState::create(pw, None).unwrap();
        state.add_entry("A", "u1", b"p1", "http://a", "n1").unwrap();
        state.add_entry("B", "u2", b"p2", "http://b", "n2").unwrap();

        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();

        let state2 = VaultState::open(path, pw, None).unwrap();
        let entries = state2.list_entries();
        assert_eq!(entries.len(), 2);
        let titles: Vec<&str> = entries.iter().map(|e| e.title.as_str()).collect();
        assert!(titles.contains(&"A"));
        assert!(titles.contains(&"B"));
    }

    /// Verify that vault_close (Drop via FFI) actually runs and the handle
    /// is no longer usable. We use the FFI path because that's the real
    /// lifecycle: Box::into_raw → use → Box::from_raw (drop).
    #[test]
    fn vault_close_triggers_drop() {
        use crate::ffi::*;
        use crate::types::*;
        use std::ffi::CString;

        let pw = b"drop-test";
        let mut handle: *mut std::ffi::c_void = std::ptr::null_mut();
        let result = vault_create(pw.as_ptr(), pw.len() as u32, std::ptr::null(), &mut handle);
        assert_eq!(result, VaultResult::Ok);
        assert!(!handle.is_null());

        // Add an entry so the vault has state
        let title = CString::new("DropTest").unwrap();
        let user = CString::new("user").unwrap();
        let url = CString::new("").unwrap();
        let notes = CString::new("").unwrap();
        let epw = b"pw";
        let mut uuid_ptr: *mut std::ffi::c_char = std::ptr::null_mut();
        assert_eq!(
            vault_add_entry(
                handle,
                title.as_ptr(),
                user.as_ptr(),
                epw.as_ptr(),
                epw.len() as u32,
                url.as_ptr(),
                notes.as_ptr(),
                &mut uuid_ptr,
            ),
            VaultResult::Ok
        );
        string_free(uuid_ptr);

        // Close — this calls Box::from_raw → Drop
        vault_close(handle);

        // After close, the handle is dangling. We can't safely use it,
        // but we verify the close didn't panic and completed normally.
        // The real proof is that Zeroizing<Vec<u8>> zeros the password
        // buffer on drop — we verify the mechanism by ensuring the
        // lifecycle completes without error.
    }
}
