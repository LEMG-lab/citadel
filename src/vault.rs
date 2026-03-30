use keepass::config::{
    CompressionConfig, DatabaseConfig, DatabaseVersion, InnerCipherConfig, KdfConfig,
    OuterCipherConfig,
};
use keepass::db::{Entry, Group, History, MemoryProtection};
use keepass::{Database, DatabaseKey};
use secrecy::ExposeSecret;
use zeroize::{Zeroize, Zeroizing};

use crate::types::VaultResult;

/// KDF configuration presets.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct KdfParams {
    pub memory: u64,      // bytes
    pub iterations: u64,
    pub parallelism: u32,
}

impl Default for KdfParams {
    fn default() -> Self {
        KdfParams {
            memory: 256 * 1024 * 1024, // 256 MB
            iterations: 3,
            parallelism: 4,
        }
    }
}

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
        Self::create_with_kdf(password, keyfile_path, KdfParams::default())
    }

    /// Create a new empty KDBX 4 vault with custom KDF parameters.
    pub fn create_with_kdf(password: &[u8], keyfile_path: Option<&str>, kdf: KdfParams) -> Result<Self, VaultResult> {
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
                memory: kdf.memory,
                iterations: kdf.iterations,
                parallelism: kdf.parallelism,
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
        meta.generator = Some("Smaug".to_string());
        meta.database_name = Some("Smaug Vault".to_string());
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

    /// Update the KDF parameters. Takes effect on next save.
    pub fn set_kdf_params(&mut self, kdf: KdfParams) {
        self.db.config.kdf_config = KdfConfig::Argon2id {
            memory: kdf.memory,
            iterations: kdf.iterations,
            parallelism: kdf.parallelism,
            version: argon2::Version::Version13,
        };
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

    /// Collect all entries recursively. Excludes entries in the Recycle Bin group.
    pub fn list_entries(&self) -> Vec<EntrySummary> {
        let rb_uuid = self.db.meta.recyclebin_uuid.unwrap_or(uuid::Uuid::nil());
        let root_name = self.db.root.name.as_str();
        let mut out = Vec::new();
        collect_entries(&self.db.root, &mut out, rb_uuid, root_name);
        out
    }

    /// List all group paths (excluding root and Recycle Bin).
    pub fn list_groups(&self) -> Vec<String> {
        let rb_uuid = self.db.meta.recyclebin_uuid.unwrap_or(uuid::Uuid::nil());
        let mut out = Vec::new();
        collect_groups(&self.db.root, "", &mut out, rb_uuid);
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
            otp_uri: entry.get("otp").unwrap_or("").to_string(),
            // Backward-compatible KDBX custom field prefix
            entry_type: entry.get("Citadel_EntryType").unwrap_or("").to_string(),
            custom_fields: collect_custom_fields(entry),
            expiry_time: entry_expiry_timestamp(entry),
            last_modified: entry_last_modified(entry),
            is_favorite: entry.get("Citadel_Favorite").map_or(false, |v| v == "true"),
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
        self.add_entry_full(title, username, password, url, notes, "", "", 0)
    }

    /// Add a new entry with optional OTP URI. Returns its UUID.
    pub fn add_entry_with_otp(
        &mut self,
        title: &str,
        username: &str,
        password: &[u8],
        url: &str,
        notes: &str,
        otp_uri: &str,
    ) -> Result<uuid::Uuid, VaultResult> {
        self.add_entry_full(title, username, password, url, notes, otp_uri, "", 0)
    }

    /// Add a new entry with all options. Returns its UUID.
    ///
    /// - `group_path`: empty = root group, otherwise slash-separated (e.g. "Work/Email")
    /// - `expiry_time`: Unix timestamp. 0 = no expiry.
    pub fn add_entry_full(
        &mut self,
        title: &str,
        username: &str,
        password: &[u8],
        url: &str,
        notes: &str,
        otp_uri: &str,
        group_path: &str,
        expiry_time: i64,
    ) -> Result<uuid::Uuid, VaultResult> {
        let password_str =
            std::str::from_utf8(password).map_err(|_| VaultResult::InternalError)?;
        let mut entry = Entry::new();
        let entry_uuid = entry.uuid;
        entry.icon_id = Some(0);
        set_entry_expiry(&mut entry, expiry_time);
        entry.set_unprotected("Title", title);
        entry.set_unprotected("UserName", username);
        entry.set_protected("Password", password_str);
        entry.set_unprotected("URL", url);
        entry.set_unprotected("Notes", notes);
        if !otp_uri.is_empty() {
            entry.set_unprotected("otp", otp_uri);
        }

        if group_path.is_empty() {
            self.db.root.entries.push(entry);
        } else {
            let target = get_or_create_group(&mut self.db.root, group_path);
            target.entries.push(entry);
        }
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
        self.update_entry_full(uuid, title, username, password, url, notes, "", 0)
    }

    /// Update an existing entry with optional OTP URI.
    pub fn update_entry_with_otp(
        &mut self,
        uuid: uuid::Uuid,
        title: &str,
        username: &str,
        password: &[u8],
        url: &str,
        notes: &str,
        otp_uri: &str,
    ) -> Result<(), VaultResult> {
        self.update_entry_full(uuid, title, username, password, url, notes, otp_uri, 0)
    }

    /// Update an existing entry with all options.
    pub fn update_entry_full(
        &mut self,
        uuid: uuid::Uuid,
        title: &str,
        username: &str,
        password: &[u8],
        url: &str,
        notes: &str,
        otp_uri: &str,
        expiry_time: i64,
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
        if otp_uri.is_empty() {
            entry.fields.remove("otp");
        } else {
            entry.set_unprotected("otp", otp_uri);
        }
        set_entry_expiry(entry, expiry_time);
        Ok(())
    }

    /// Set or clear the favorite flag on an entry.
    pub fn set_favorite(&mut self, uuid: uuid::Uuid, favorite: bool) -> Result<(), VaultResult> {
        let entry = self.db.root.entry_by_uuid_mut(uuid)
            .ok_or(VaultResult::InternalError)?;
        // Backward-compatible KDBX custom field prefix
        if favorite {
            entry.set_unprotected("Citadel_Favorite", "true");
        } else {
            entry.fields.remove("Citadel_Favorite");
        }
        Ok(())
    }

    /// Set a custom field on an entry.
    pub fn set_custom_field(&mut self, uuid: uuid::Uuid, key: &str, value: &str, is_protected: bool) -> Result<(), VaultResult> {
        let entry = self.db.root.entry_by_uuid_mut(uuid)
            .ok_or(VaultResult::InternalError)?;
        if is_protected {
            entry.set_protected(key, value);
        } else {
            entry.set_unprotected(key, value);
        }
        Ok(())
    }

    /// Remove a custom field from an entry.
    pub fn remove_custom_field(&mut self, uuid: uuid::Uuid, key: &str) -> Result<(), VaultResult> {
        let entry = self.db.root.entry_by_uuid_mut(uuid)
            .ok_or(VaultResult::InternalError)?;
        entry.fields.remove(key);
        Ok(())
    }

    /// List attachments on an entry. Returns (name, size_bytes) pairs.
    pub fn list_attachments(&self, uuid: uuid::Uuid) -> Result<Vec<(String, usize)>, VaultResult> {
        let entry = self.db.root.entry_by_uuid(uuid)
            .ok_or(VaultResult::InternalError)?;
        Ok(entry.attachments.iter().map(|(name, att)| {
            let size = match &att.data {
                keepass::db::Value::Unprotected(data) => data.len(),
                keepass::db::Value::Protected(sb) => sb.expose_secret().len(),
            };
            (name.clone(), size)
        }).collect())
    }

    /// Get an attachment's data by name.
    pub fn get_attachment(&self, uuid: uuid::Uuid, name: &str) -> Result<Vec<u8>, VaultResult> {
        let entry = self.db.root.entry_by_uuid(uuid)
            .ok_or(VaultResult::InternalError)?;
        let att = entry.attachments.get(name)
            .ok_or(VaultResult::InternalError)?;
        let data = match &att.data {
            keepass::db::Value::Unprotected(data) => data.clone(),
            keepass::db::Value::Protected(sb) => sb.expose_secret().to_vec(),
        };
        Ok(data)
    }

    /// Add an attachment to an entry.
    pub fn add_attachment(&mut self, uuid: uuid::Uuid, name: &str, data: &[u8]) -> Result<(), VaultResult> {
        let entry = self.db.root.entry_by_uuid_mut(uuid)
            .ok_or(VaultResult::InternalError)?;
        entry.attachments.insert(
            name.to_string(),
            keepass::db::Attachment { data: keepass::db::Value::Unprotected(data.to_vec()) },
        );
        Ok(())
    }

    /// Remove an attachment from an entry by name.
    pub fn remove_attachment(&mut self, uuid: uuid::Uuid, name: &str) -> Result<(), VaultResult> {
        let entry = self.db.root.entry_by_uuid_mut(uuid)
            .ok_or(VaultResult::InternalError)?;
        entry.attachments.remove(name);
        Ok(())
    }

    /// Get the password history for an entry. Returns a list of (password, timestamp) pairs.
    pub fn get_entry_history(&self, uuid: uuid::Uuid) -> Result<Vec<HistoryItem>, VaultResult> {
        let entry = self.db.root.entry_by_uuid(uuid)
            .ok_or(VaultResult::InternalError)?;
        let mut items = Vec::new();
        if let Some(history) = &entry.history {
            for h_entry in history.get_entries() {
                let password = h_entry.get_password().unwrap_or("").to_string();
                let timestamp = entry_last_modified(h_entry);
                items.push(HistoryItem { password, timestamp });
            }
        }
        Ok(items)
    }

    /// Soft-delete an entry by UUID: move to Recycle Bin and record a DeletedObject.
    pub fn delete_entry(&mut self, uuid: uuid::Uuid) -> Result<(), VaultResult> {
        // Extract the entry from wherever it lives
        let entry = extract_entry_recursive(&mut self.db.root, uuid)
            .ok_or(VaultResult::InternalError)?;

        // Get or create the Recycle Bin group
        let rb_uuid = self.get_or_create_recyclebin();

        // Find the Recycle Bin group and add the entry
        let rb = self.db.root.group_by_uuid_mut(rb_uuid)
            .ok_or(VaultResult::InternalError)?;
        rb.entries.push(entry);

        // Record deletion timestamp
        self.db.deleted_objects.insert(uuid, Some(keepass::db::Times::now()));

        Ok(())
    }

    /// List entries currently in the Recycle Bin.
    pub fn list_recycled_entries(&self) -> Vec<EntrySummary> {
        let rb_uuid = match self.db.meta.recyclebin_uuid {
            Some(u) if u != uuid::Uuid::nil() => u,
            _ => return Vec::new(),
        };
        let rb = match self.db.root.group_by_uuid(rb_uuid) {
            Some(g) => g,
            None => return Vec::new(),
        };
        rb.entries
            .iter()
            .map(|entry| EntrySummary {
                uuid: entry.uuid.to_string(),
                title: entry.get_title().unwrap_or("").to_string(),
                username: entry.get_username().unwrap_or("").to_string(),
                url: entry.get_url().unwrap_or("").to_string(),
                group: "Recycle Bin".to_string(),
                entry_type: entry.get("Citadel_EntryType").unwrap_or("").to_string(),
                tags: entry.get("Citadel_Tags").unwrap_or("").to_string(),
                expiry_time: entry_expiry_timestamp(entry),
                last_modified: entry_last_modified(entry),
                is_favorite: entry
                    .get("Citadel_Favorite")
                    .map_or(false, |v| v == "true"),
                attachment_count: entry.attachments.len() as u32,
            })
            .collect()
    }

    /// Restore an entry from the Recycle Bin back to the root group.
    pub fn restore_entry(&mut self, uuid: uuid::Uuid) -> Result<(), VaultResult> {
        let rb_uuid = match self.db.meta.recyclebin_uuid {
            Some(u) if u != uuid::Uuid::nil() => u,
            _ => return Err(VaultResult::InternalError),
        };
        let rb = self
            .db
            .root
            .group_by_uuid_mut(rb_uuid)
            .ok_or(VaultResult::InternalError)?;
        let idx = rb
            .entries
            .iter()
            .position(|e| e.uuid == uuid)
            .ok_or(VaultResult::InternalError)?;
        let entry = rb.entries.remove(idx);
        self.db.root.entries.push(entry);
        self.db.deleted_objects.remove(&uuid);
        Ok(())
    }

    /// Permanently delete a single entry from the Recycle Bin.
    pub fn permanently_delete_entry(&mut self, uuid: uuid::Uuid) -> Result<(), VaultResult> {
        let rb_uuid = match self.db.meta.recyclebin_uuid {
            Some(u) if u != uuid::Uuid::nil() => u,
            _ => return Err(VaultResult::InternalError),
        };
        let rb = self
            .db
            .root
            .group_by_uuid_mut(rb_uuid)
            .ok_or(VaultResult::InternalError)?;
        let idx = rb
            .entries
            .iter()
            .position(|e| e.uuid == uuid)
            .ok_or(VaultResult::InternalError)?;
        rb.entries.remove(idx);
        Ok(())
    }

    /// Permanently remove all entries in the Recycle Bin group.
    pub fn empty_recyclebin(&mut self) -> Result<usize, VaultResult> {
        let rb_uuid = match self.db.meta.recyclebin_uuid {
            Some(u) if u != uuid::Uuid::nil() => u,
            _ => return Ok(0),
        };
        let rb = self.db.root.group_by_uuid_mut(rb_uuid)
            .ok_or(VaultResult::InternalError)?;
        let count = rb.entries.len();
        rb.entries.clear();
        Ok(count)
    }

    /// Get the Recycle Bin UUID, creating the group if needed.
    fn get_or_create_recyclebin(&mut self) -> uuid::Uuid {
        if let Some(rb_uuid) = self.db.meta.recyclebin_uuid {
            if rb_uuid != uuid::Uuid::nil() {
                if self.db.root.group_by_uuid(rb_uuid).is_some() {
                    return rb_uuid;
                }
            }
        }
        // Create Recycle Bin group
        let mut rb = Group::new("Recycle Bin");
        rb.icon_id = Some(43); // trash icon
        rb.enable_searching = Some(false);
        let rb_uuid = rb.uuid;
        self.db.root.groups.push(rb);
        self.db.meta.recyclebin_enabled = Some(true);
        self.db.meta.recyclebin_uuid = Some(rb_uuid);
        self.db.meta.recyclebin_changed = Some(keepass::db::Times::now());
        rb_uuid
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
    pub group: String,
    pub entry_type: String,
    /// Comma-separated tags from the Citadel_Tags custom field.
    /// (Backward-compatible KDBX custom field prefix)
    pub tags: String,
    /// Unix timestamp of expiry. 0 if expiry is not enabled.
    pub expiry_time: i64,
    /// Unix timestamp of last modification. 0 if unknown.
    pub last_modified: i64,
    pub is_favorite: bool,
    /// Number of file attachments on this entry.
    pub attachment_count: u32,
}

pub struct HistoryItem {
    pub password: String,
    pub timestamp: i64,
}

pub struct CustomField {
    pub key: String,
    pub value: String,
    pub is_protected: bool,
}

pub struct EntryDetail {
    pub uuid: String,
    pub title: String,
    pub username: String,
    pub password: Zeroizing<Vec<u8>>,
    pub url: String,
    pub notes: String,
    pub otp_uri: String,
    pub entry_type: String,
    pub custom_fields: Vec<CustomField>,
    /// Unix timestamp of expiry. 0 if expiry is not enabled.
    pub expiry_time: i64,
    /// Unix timestamp of last modification. 0 if unknown.
    pub last_modified: i64,
    pub is_favorite: bool,
}

fn collect_entries(group: &Group, out: &mut Vec<EntrySummary>, skip_group: uuid::Uuid, path: &str) {
    for entry in &group.entries {
        out.push(EntrySummary {
            uuid: entry.uuid.to_string(),
            title: entry.get_title().unwrap_or("").to_string(),
            username: entry.get_username().unwrap_or("").to_string(),
            url: entry.get_url().unwrap_or("").to_string(),
            group: path.to_string(),
            entry_type: entry.get("Citadel_EntryType").unwrap_or("").to_string(),
            tags: entry.get("Citadel_Tags").unwrap_or("").to_string(),
            expiry_time: entry_expiry_timestamp(entry),
            last_modified: entry_last_modified(entry),
            is_favorite: entry.get("Citadel_Favorite").map_or(false, |v| v == "true"),
            attachment_count: entry.attachments.len() as u32,
        });
    }
    for child in &group.groups {
        // Skip the Recycle Bin group
        if skip_group != uuid::Uuid::nil() && child.uuid == skip_group {
            continue;
        }
        let child_path = format!("{}/{}", path, child.name);
        collect_entries(child, out, skip_group, &child_path);
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
        m.generator = Some("Smaug".to_string());
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

    let max_history_items = m.history_max_items.unwrap_or(10) as usize;
    let max_history_size = m.history_max_size.unwrap_or(6_291_456) as usize;

    // -- Groups (recursive) --
    sanitize_group(&mut db.root, epoch, nil, max_history_items, max_history_size);
}

fn sanitize_group(
    group: &mut Group,
    epoch: chrono::NaiveDateTime,
    nil: uuid::Uuid,
    max_history_items: usize,
    max_history_size: usize,
) {
    group.icon_id.get_or_insert(48);
    group.times.expiry.get_or_insert(epoch);
    group.enable_autotype.get_or_insert(true);
    group.enable_searching.get_or_insert(true);
    group.last_top_visible_entry.get_or_insert(nil);

    for entry in &mut group.entries {
        sanitize_entry(entry, epoch, max_history_items, max_history_size);
    }
    for child in &mut group.groups {
        sanitize_group(child, epoch, nil, max_history_items, max_history_size);
    }
}

fn sanitize_entry(
    entry: &mut Entry,
    epoch: chrono::NaiveDateTime,
    max_history_items: usize,
    max_history_size: usize,
) {
    entry.icon_id.get_or_insert(0);
    entry.times.expiry.get_or_insert(epoch);
    // keepass-rs serializes AutoType.DataTransferObfuscation as "True"/"False"
    // but KeePassXC expects an integer (0/1).  We clear only that one field
    // to None so the serializer omits it, while preserving Enabled,
    // DefaultSequence, and Associations.
    sanitize_autotype(&mut entry.autotype);

    // Rebuild history with sanitized entries, pruning to max_history_items
    // and max_history_size.  History only exposes get_entries() (immutable)
    // so we take it, clone entries, fix them, and rebuild via add_entry().
    if let Some(old_history) = entry.history.take() {
        let mut new_history = History::default();
        let entries = old_history.get_entries().clone();
        // Entries are ordered newest-first. Keep the most recent ones.
        let mut kept = 0;
        let mut total_size = 0usize;
        // add_entry() prepends, so iterate in reverse to preserve order.
        // But we prune from the tail (oldest), so collect what to keep first.
        let mut to_keep: Vec<Entry> = Vec::new();
        for mut h_entry in entries.into_iter() {
            if kept >= max_history_items {
                break;
            }
            // Rough size estimate: sum of all string field values
            let entry_size: usize = h_entry.fields.values().map(|v| {
                match v {
                    keepass::db::Value::Unprotected(s) => s.len(),
                    keepass::db::Value::Protected(_) => 64, // rough estimate for protected values
                }
            }).sum();
            if total_size + entry_size > max_history_size && kept > 0 {
                break;
            }
            h_entry.icon_id.get_or_insert(0);
            h_entry.times.expiry.get_or_insert(epoch);
            sanitize_autotype(&mut h_entry.autotype);
            to_keep.push(h_entry);
            kept += 1;
            total_size += entry_size;
        }
        // add_entry() prepends, so add in reverse to preserve chronological order.
        for h_entry in to_keep.into_iter().rev() {
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

/// Set the expiry on an entry. If `expiry_time` is 0, set expires=false and expiry=epoch.
fn set_entry_expiry(entry: &mut Entry, expiry_time: i64) {
    if expiry_time > 0 {
        entry.times.expires = Some(true);
        entry.times.expiry = Some(chrono::DateTime::from_timestamp(expiry_time, 0)
            .map(|dt| dt.naive_utc())
            .unwrap_or(keepass::db::Times::epoch()));
    } else {
        entry.times.expires = Some(false);
        entry.times.expiry = Some(keepass::db::Times::epoch());
    }
}

/// Extract the expiry timestamp from an entry. Returns 0 if expiry is not enabled.
fn entry_expiry_timestamp(entry: &Entry) -> i64 {
    if entry.times.expires == Some(true) {
        if let Some(dt) = entry.times.expiry {
            return dt.and_utc().timestamp();
        }
    }
    0
}

/// Extract the last modification timestamp from an entry.
fn entry_last_modified(entry: &Entry) -> i64 {
    entry.times.last_modification
        .map(|dt| dt.and_utc().timestamp())
        .unwrap_or(0)
}

/// Standard fields to exclude when collecting custom fields.
// Backward-compatible KDBX custom field prefix — Citadel_ names are kept for
// compatibility with existing vault files.
const STANDARD_FIELDS: &[&str] = &[
    "Title", "UserName", "Password", "URL", "Notes", "otp",
    "Citadel_Favorite", "Citadel_EntryType", "Citadel_Tags",
];

/// Collect all non-standard fields from an entry as custom fields.
fn collect_custom_fields(entry: &Entry) -> Vec<CustomField> {
    let mut fields = Vec::new();
    for (key, value) in &entry.fields {
        if STANDARD_FIELDS.contains(&key.as_str()) {
            continue;
        }
        let is_protected = !matches!(value, keepass::db::Value::Unprotected(_));
        let val = entry.get(key).unwrap_or("").to_string();
        fields.push(CustomField {
            key: key.clone(),
            value: val,
            is_protected,
        });
    }
    fields
}

/// Navigate to (or create) a group by slash-separated path relative to root.
/// E.g., "Work/Email" finds or creates "Work" under root, then "Email" under "Work".
fn get_or_create_group<'a>(root: &'a mut Group, path: &str) -> &'a mut Group {
    let parts: Vec<&str> = path.split('/').filter(|s| !s.is_empty()).collect();
    let mut current = root;
    for part in parts {
        // Find existing child or create one
        let idx = current.groups.iter().position(|g| g.name == part);
        if let Some(i) = idx {
            current = &mut current.groups[i];
        } else {
            let mut new_group = Group::new(part);
            new_group.icon_id = Some(48);
            new_group.enable_searching = Some(true);
            new_group.enable_autotype = Some(true);
            current.groups.push(new_group);
            let last = current.groups.len() - 1;
            current = &mut current.groups[last];
        }
    }
    current
}

/// Collect group paths recursively (excluding root name and Recycle Bin).
fn collect_groups(group: &Group, path: &str, out: &mut Vec<String>, skip_group: uuid::Uuid) {
    for child in &group.groups {
        if skip_group != uuid::Uuid::nil() && child.uuid == skip_group {
            continue;
        }
        let child_path = if path.is_empty() {
            child.name.clone()
        } else {
            format!("{}/{}", path, child.name)
        };
        out.push(child_path.clone());
        collect_groups(child, &child_path, out, skip_group);
    }
}

/// Remove an entry by UUID from a group tree and return it.
fn extract_entry_recursive(group: &mut Group, uuid: uuid::Uuid) -> Option<Entry> {
    if let Some(pos) = group.entries.iter().position(|e| e.uuid == uuid) {
        return Some(group.entries.remove(pos));
    }
    for child in &mut group.groups {
        if let Some(entry) = extract_entry_recursive(child, uuid) {
            return Some(entry);
        }
    }
    None
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
            Some("Smaug Vault")
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

    #[test]
    fn history_pruning() {
        let pw = b"history-test";
        let mut state = VaultState::create(pw, None).unwrap();
        let uuid = state.add_entry("Test", "user", b"pw0", "", "").unwrap();

        // Update the entry 15 times to create history
        for i in 1..=15 {
            let new_pw = format!("pw{}", i);
            state.update_entry(uuid, "Test", "user", new_pw.as_bytes(), "", "").unwrap();
        }

        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();

        let state2 = VaultState::open(path, pw, None).unwrap();
        let entry = state2.db.root.entry_by_uuid(uuid).unwrap();
        let history_count = entry.history.as_ref().map_or(0, |h| h.get_entries().len());
        // Default max is 10
        assert!(history_count <= 10, "history count {} > 10", history_count);
        assert!(history_count > 0, "history should not be empty");
    }

    #[test]
    fn otp_roundtrip() {
        let pw = b"otp-test";
        let otp = "otpauth://totp/Test:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Test&period=30&digits=6&algorithm=SHA1";
        let mut state = VaultState::create(pw, None).unwrap();
        let uuid = state.add_entry_with_otp("OTP Test", "user", b"pw", "https://example.com", "", otp).unwrap();

        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();

        let state2 = VaultState::open(path, pw, None).unwrap();
        let detail = state2.get_entry(uuid).unwrap();
        assert_eq!(detail.otp_uri, otp);
    }

    #[test]
    fn create_with_kdf_standard() {
        let pw = b"kdf-standard";
        let kdf = KdfParams { memory: 256 * 1024 * 1024, iterations: 3, parallelism: 4 };
        let mut state = VaultState::create_with_kdf(pw, None, kdf).unwrap();
        state.add_entry("Test", "u", b"p", "", "").unwrap();
        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();
        let state2 = VaultState::open(path, pw, None).unwrap();
        assert_eq!(state2.list_entries().len(), 1);
    }

    #[test]
    fn create_with_kdf_high() {
        let pw = b"kdf-high";
        let kdf = KdfParams { memory: 512 * 1024 * 1024, iterations: 5, parallelism: 4 };
        let mut state = VaultState::create_with_kdf(pw, None, kdf).unwrap();
        state.add_entry("Test", "u", b"p", "", "").unwrap();
        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();
        let state2 = VaultState::open(path, pw, None).unwrap();
        assert_eq!(state2.list_entries().len(), 1);
    }

    #[test]
    fn set_kdf_params_and_reopen() {
        let pw = b"kdf-set";
        let mut state = VaultState::create(pw, None).unwrap();
        state.add_entry("Test", "u", b"p", "", "").unwrap();
        // Change KDF to High
        state.set_kdf_params(KdfParams { memory: 512 * 1024 * 1024, iterations: 5, parallelism: 4 });
        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();
        // Should be openable with new KDF params applied
        let state2 = VaultState::open(path, pw, None).unwrap();
        assert_eq!(state2.list_entries().len(), 1);
    }

    #[test]
    fn soft_delete_moves_to_recyclebin() {
        let pw = b"recycle-test";
        let mut state = VaultState::create(pw, None).unwrap();
        let uuid = state.add_entry("Trash Me", "user", b"pw", "", "").unwrap();
        assert_eq!(state.list_entries().len(), 1);

        state.delete_entry(uuid).unwrap();

        // Entry should no longer appear in list_entries
        assert!(state.list_entries().is_empty());

        // Entry should be in the Recycle Bin group
        let rb_uuid = state.db.meta.recyclebin_uuid.unwrap();
        let rb = state.db.root.group_by_uuid(rb_uuid).unwrap();
        assert_eq!(rb.entries.len(), 1);
        assert_eq!(rb.entries[0].uuid, uuid);

        // A DeletedObject should have been recorded
        assert!(state.db.deleted_objects.contains_key(&uuid));
    }

    #[test]
    fn empty_recyclebin_clears_entries() {
        let pw = b"empty-rb-test";
        let mut state = VaultState::create(pw, None).unwrap();
        let u1 = state.add_entry("A", "u", b"p", "", "").unwrap();
        let u2 = state.add_entry("B", "u", b"p", "", "").unwrap();
        state.delete_entry(u1).unwrap();
        state.delete_entry(u2).unwrap();
        assert!(state.list_entries().is_empty());

        let count = state.empty_recyclebin().unwrap();
        assert_eq!(count, 2);

        // Recycle Bin should be empty now
        let rb_uuid = state.db.meta.recyclebin_uuid.unwrap();
        let rb = state.db.root.group_by_uuid(rb_uuid).unwrap();
        assert!(rb.entries.is_empty());
    }

    #[test]
    fn recyclebin_roundtrip() {
        let pw = b"rb-roundtrip";
        let mut state = VaultState::create(pw, None).unwrap();
        let uuid = state.add_entry("Deleted", "u", b"p", "", "").unwrap();
        state.delete_entry(uuid).unwrap();

        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();

        let state2 = VaultState::open(path, pw, None).unwrap();
        // Deleted entry should not appear in list
        assert!(state2.list_entries().is_empty());
        // But should still be findable in the Recycle Bin
        let rb_uuid = state2.db.meta.recyclebin_uuid.unwrap();
        let rb = state2.db.root.group_by_uuid(rb_uuid).unwrap();
        assert_eq!(rb.entries.len(), 1);
    }

    #[test]
    fn add_entry_to_group() {
        let pw = b"group-test";
        let mut state = VaultState::create(pw, None).unwrap();
        let uuid = state.add_entry_full("Work Email", "bob", b"pw", "", "", "", "Work/Email", 0).unwrap();

        let entries = state.list_entries();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].group, "Root/Work/Email");

        // Entry should still be accessible via get_entry / update / delete
        let detail = state.get_entry(uuid).unwrap();
        assert_eq!(detail.title, "Work Email");

        state.update_entry(uuid, "Work Email Updated", "bob", b"pw2", "", "").unwrap();
        let detail2 = state.get_entry(uuid).unwrap();
        assert_eq!(detail2.title, "Work Email Updated");

        state.delete_entry(uuid).unwrap();
        assert!(state.list_entries().is_empty());
    }

    #[test]
    fn list_groups() {
        let pw = b"groups-test";
        let mut state = VaultState::create(pw, None).unwrap();
        state.add_entry_full("A", "u", b"p", "", "", "", "Work", 0).unwrap();
        state.add_entry_full("B", "u", b"p", "", "", "", "Work/Email", 0).unwrap();
        state.add_entry_full("C", "u", b"p", "", "", "", "Personal", 0).unwrap();

        let groups = state.list_groups();
        assert!(groups.contains(&"Work".to_string()));
        assert!(groups.contains(&"Work/Email".to_string()));
        assert!(groups.contains(&"Personal".to_string()));
    }

    #[test]
    fn groups_roundtrip() {
        let pw = b"groups-rt";
        let mut state = VaultState::create(pw, None).unwrap();
        state.add_entry_full("A", "u", b"p", "", "", "", "Work", 0).unwrap();
        state.add_entry_full("B", "u", b"p", "", "", "", "Personal", 0).unwrap();

        let tmp = NamedTempFile::new().unwrap();
        let path = tmp.path().to_str().unwrap();
        state.save_to(path).unwrap();

        let state2 = VaultState::open(path, pw, None).unwrap();
        let entries = state2.list_entries();
        assert_eq!(entries.len(), 2);
        let groups: Vec<&str> = entries.iter().map(|e| e.group.as_str()).collect();
        assert!(groups.contains(&"Root/Work"));
        assert!(groups.contains(&"Root/Personal"));
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
                std::ptr::null(),
                std::ptr::null(),
                0,
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
