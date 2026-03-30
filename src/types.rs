use std::ffi::c_char;

/// Result codes returned across the FFI boundary.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VaultResult {
    Ok = 0,
    WrongPassword = 1,
    FileCorrupted = 2,
    FileNotFound = 3,
    WriteFailed = 4,
    ValidationFailed = 5,
    EmptyPassword = 6,
    InternalError = 99,
}

/// Entry summary for list operations — never contains passwords.
#[repr(C)]
pub struct CEntryListItem {
    pub uuid: *mut c_char,
    pub title: *mut c_char,
    pub username: *mut c_char,
    pub url: *mut c_char,
    pub group: *mut c_char,
    pub entry_type: *mut c_char,
    /// Comma-separated tags. Null or empty if no tags.
    pub tags: *mut c_char,
    /// Unix timestamp of expiry. 0 means no expiry set.
    pub expiry_time: i64,
    /// Unix timestamp of last modification. 0 if unknown.
    pub last_modified: i64,
    pub is_favorite: bool,
    /// Number of file attachments on this entry.
    pub attachment_count: u32,
}

/// Owned list of entry summaries, allocated by Rust, freed by `entry_list_free`.
#[repr(C)]
pub struct CEntryList {
    pub entries: *mut CEntryListItem,
    pub count: u32,
}

/// A single custom field on an entry.
#[repr(C)]
pub struct CCustomField {
    pub key: *mut c_char,
    pub value: *mut c_char,
    pub is_protected: bool,
}

/// Full entry data including password as a byte buffer (not a C string).
/// The password field points to `password_len` bytes of data. It is NOT
/// null-terminated. Allocated by Rust, freed by `entry_data_free`.
#[repr(C)]
pub struct CEntryData {
    pub uuid: *mut c_char,
    pub title: *mut c_char,
    pub username: *mut c_char,
    pub password: *mut u8,
    pub password_len: u32,
    pub url: *mut c_char,
    pub notes: *mut c_char,
    pub otp_uri: *mut c_char,
    pub entry_type: *mut c_char,
    pub custom_fields: *mut CCustomField,
    pub custom_field_count: u32,
    /// Unix timestamp of expiry. 0 means no expiry set.
    pub expiry_time: i64,
    /// Unix timestamp of last modification. 0 if unknown.
    pub last_modified: i64,
    pub is_favorite: bool,
}

/// A single password history item.
#[repr(C)]
pub struct CHistoryItem {
    pub password: *mut c_char,
    /// Unix timestamp of when this password was set.
    pub timestamp: i64,
}

/// List of password history items, allocated by Rust, freed by `history_list_free`.
#[repr(C)]
pub struct CHistoryList {
    pub items: *mut CHistoryItem,
    pub count: u32,
}

/// A single attachment info item (name + size).
#[repr(C)]
pub struct CAttachmentInfo {
    pub name: *mut c_char,
    pub size: u64,
}

/// List of attachment info items, allocated by Rust, freed by `attachment_list_free`.
#[repr(C)]
pub struct CAttachmentList {
    pub items: *mut CAttachmentInfo,
    pub count: u32,
}

/// Raw attachment data, allocated by Rust, freed by `attachment_data_free`.
#[repr(C)]
pub struct CAttachmentData {
    pub data: *mut u8,
    pub len: u64,
}

/// Bitmask flags for password character sets.
#[repr(C)]
pub struct CharsetFlags;

impl CharsetFlags {
    pub const LOWERCASE: u32 = 1;
    pub const UPPERCASE: u32 = 2;
    pub const DIGITS: u32 = 4;
    pub const SYMBOLS: u32 = 8;
}
