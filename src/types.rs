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
}

/// Owned list of entry summaries, allocated by Rust, freed by `entry_list_free`.
#[repr(C)]
pub struct CEntryList {
    pub entries: *mut CEntryListItem,
    pub count: u32,
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
