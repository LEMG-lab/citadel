use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::catch_unwind;
use std::slice;
use zeroize::{Zeroize, Zeroizing};

use crate::password;
use crate::types::*;
use crate::vault::{KdfParams, VaultState};

// ---------------------------------------------------------------------------
// Thread safety
// ---------------------------------------------------------------------------
//
// Vault handles (`*mut c_void` returned by `vault_open` / `vault_create`) are
// **NOT thread-safe**.  The underlying `VaultState` contains no internal
// synchronization.  All calls that share the same handle must be serialized by
// the caller.  Passing the same handle to multiple threads concurrently is
// undefined behaviour.  Each handle should be owned by exactly one thread (or
// protected by an external mutex).

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Convert a nullable C string to &str, returning "" for null.
unsafe fn cstr_to_str<'a>(ptr: *const c_char) -> &'a str {
    if ptr.is_null() {
        ""
    } else {
        CStr::from_ptr(ptr).to_str().unwrap_or("")
    }
}

/// Allocate a C string on the heap from a Rust &str. Returns null for empty.
fn str_to_c(s: &str) -> *mut c_char {
    CString::new(s).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// Free a C string allocated by `str_to_c`.
unsafe fn free_c_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Read a password from FFI pointer+len into Zeroizing<Vec<u8>>.
unsafe fn read_password(ptr: *const u8, len: u32) -> Zeroizing<Vec<u8>> {
    if ptr.is_null() || len == 0 {
        Zeroizing::new(Vec::new())
    } else {
        Zeroizing::new(slice::from_raw_parts(ptr, len as usize).to_vec())
    }
}

// ---------------------------------------------------------------------------
// Vault lifecycle
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn vault_open(
    path: *const c_char,
    password_ptr: *const u8,
    password_len: u32,
    keyfile_path: *const c_char,
    handle_out: *mut *mut c_void,
) -> VaultResult {
    if path.is_null() || handle_out.is_null() {
        return VaultResult::InternalError;
    }
    crate::memory::disable_core_dumps();
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let path_str = unsafe { cstr_to_str(path) };
        let pw = unsafe { read_password(password_ptr, password_len) };
        let kf = if keyfile_path.is_null() {
            None
        } else {
            let s = unsafe { cstr_to_str(keyfile_path) };
            if s.is_empty() { None } else { Some(s) }
        };
        match VaultState::open(path_str, &pw, kf) {
            Ok(state) => {
                let boxed = Box::new(state);
                unsafe {
                    *handle_out = Box::into_raw(boxed) as *mut c_void;
                }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_create(
    password_ptr: *const u8,
    password_len: u32,
    keyfile_path: *const c_char,
    handle_out: *mut *mut c_void,
) -> VaultResult {
    if handle_out.is_null() {
        return VaultResult::InternalError;
    }
    crate::memory::disable_core_dumps();
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let pw = unsafe { read_password(password_ptr, password_len) };
        let kf = if keyfile_path.is_null() {
            None
        } else {
            let s = unsafe { cstr_to_str(keyfile_path) };
            if s.is_empty() { None } else { Some(s) }
        };
        match VaultState::create(&pw, kf) {
            Ok(state) => {
                let boxed = Box::new(state);
                unsafe {
                    *handle_out = Box::into_raw(boxed) as *mut c_void;
                }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Create a vault with custom KDF parameters.
/// kdf_memory is in bytes, kdf_iterations is the iteration count, kdf_parallelism is thread count.
#[no_mangle]
pub extern "C" fn vault_create_with_kdf(
    password_ptr: *const u8,
    password_len: u32,
    keyfile_path: *const c_char,
    kdf_memory: u64,
    kdf_iterations: u64,
    kdf_parallelism: u32,
    handle_out: *mut *mut c_void,
) -> VaultResult {
    if handle_out.is_null() {
        return VaultResult::InternalError;
    }
    crate::memory::disable_core_dumps();
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let pw = unsafe { read_password(password_ptr, password_len) };
        let kf = if keyfile_path.is_null() {
            None
        } else {
            let s = unsafe { cstr_to_str(keyfile_path) };
            if s.is_empty() { None } else { Some(s) }
        };
        let kdf = KdfParams { memory: kdf_memory, iterations: kdf_iterations, parallelism: kdf_parallelism };
        match VaultState::create_with_kdf(&pw, kf, kdf) {
            Ok(state) => {
                let boxed = Box::new(state);
                unsafe {
                    *handle_out = Box::into_raw(boxed) as *mut c_void;
                }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Update the KDF parameters on an open vault. Takes effect on next save.
#[no_mangle]
pub extern "C" fn vault_set_kdf_params(
    handle: *mut c_void,
    kdf_memory: u64,
    kdf_iterations: u64,
    kdf_parallelism: u32,
) -> VaultResult {
    if handle.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let kdf = KdfParams { memory: kdf_memory, iterations: kdf_iterations, parallelism: kdf_parallelism };
        state.set_kdf_params(kdf);
        VaultResult::Ok
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_save_to(handle: *mut c_void, path: *const c_char) -> VaultResult {
    if handle.is_null() || path.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let path_str = unsafe { cstr_to_str(path) };
        match state.save_to(path_str) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_validate(
    path: *const c_char,
    password_ptr: *const u8,
    password_len: u32,
    keyfile_path: *const c_char,
) -> VaultResult {
    if path.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let path_str = unsafe { cstr_to_str(path) };
        let pw = unsafe { read_password(password_ptr, password_len) };
        let kf = if keyfile_path.is_null() {
            None
        } else {
            let s = unsafe { cstr_to_str(keyfile_path) };
            if s.is_empty() { None } else { Some(s) }
        };
        match VaultState::validate(path_str, &pw, kf) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_close(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| {
        // Reconstruct the Box so it gets dropped (and Zeroizing fields are zeroed).
        unsafe {
            drop(Box::from_raw(handle as *mut VaultState));
        }
    }));
}

#[no_mangle]
pub extern "C" fn vault_change_password(
    handle: *mut c_void,
    new_password_ptr: *const u8,
    new_password_len: u32,
    new_keyfile_path: *const c_char,
) -> VaultResult {
    if handle.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let pw = unsafe { read_password(new_password_ptr, new_password_len) };
        let kf = if new_keyfile_path.is_null() {
            None
        } else {
            let s = unsafe { cstr_to_str(new_keyfile_path) };
            if s.is_empty() { None } else { Some(s) }
        };
        match state.change_password(&pw, kf) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

// ---------------------------------------------------------------------------
// Entry operations
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn vault_list_entries(
    handle: *mut c_void,
    list_out: *mut *mut CEntryList,
) -> VaultResult {
    if handle.is_null() || list_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &*(handle as *const VaultState) };
        let summaries = state.list_entries();

        let count = summaries.len() as u32;
        let items: Vec<CEntryListItem> = summaries
            .iter()
            .map(|s| CEntryListItem {
                uuid: str_to_c(&s.uuid),
                title: str_to_c(&s.title),
                username: str_to_c(&s.username),
                url: str_to_c(&s.url),
                group: str_to_c(&s.group),
                entry_type: str_to_c(&s.entry_type),
                tags: str_to_c(&s.tags),
                expiry_time: s.expiry_time,
                last_modified: s.last_modified,
                is_favorite: s.is_favorite,
                attachment_count: s.attachment_count,
            })
            .collect();

        let items_ptr = if items.is_empty() {
            std::ptr::null_mut()
        } else {
            let mut items = items.into_boxed_slice();
            let ptr = items.as_mut_ptr();
            std::mem::forget(items);
            ptr
        };

        let list = Box::new(CEntryList {
            entries: items_ptr,
            count,
        });
        unsafe {
            *list_out = Box::into_raw(list);
        }
        VaultResult::Ok
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_get_entry(
    handle: *mut c_void,
    uuid_str: *const c_char,
    entry_out: *mut *mut CEntryData,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() || entry_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &*(handle as *const VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        match state.get_entry(uuid) {
            Ok(detail) => {
                let pw_len = detail.password.len() as u32;
                let pw_ptr = if detail.password.is_empty() {
                    std::ptr::null_mut()
                } else {
                    let pw_buf: Vec<u8> = detail.password.to_vec();
                    let boxed = pw_buf.into_boxed_slice();
                    Box::into_raw(boxed) as *mut u8
                };
                // Build custom fields array
                let cf_count = detail.custom_fields.len() as u32;
                let cf_ptr = if detail.custom_fields.is_empty() {
                    std::ptr::null_mut()
                } else {
                    let cfs: Vec<CCustomField> = detail.custom_fields.iter().map(|f| {
                        CCustomField {
                            key: str_to_c(&f.key),
                            value: str_to_c(&f.value),
                            is_protected: f.is_protected,
                        }
                    }).collect();
                    let mut boxed = cfs.into_boxed_slice();
                    let ptr = boxed.as_mut_ptr();
                    std::mem::forget(boxed);
                    ptr
                };

                let data = Box::new(CEntryData {
                    uuid: str_to_c(&detail.uuid),
                    title: str_to_c(&detail.title),
                    username: str_to_c(&detail.username),
                    password: pw_ptr,
                    password_len: pw_len,
                    url: str_to_c(&detail.url),
                    notes: str_to_c(&detail.notes),
                    otp_uri: str_to_c(&detail.otp_uri),
                    entry_type: str_to_c(&detail.entry_type),
                    custom_fields: cf_ptr,
                    custom_field_count: cf_count,
                    expiry_time: detail.expiry_time,
                    last_modified: detail.last_modified,
                    is_favorite: detail.is_favorite,
                });
                unsafe {
                    *entry_out = Box::into_raw(data);
                }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_add_entry(
    handle: *mut c_void,
    title: *const c_char,
    username: *const c_char,
    password_ptr: *const u8,
    password_len: u32,
    url: *const c_char,
    notes: *const c_char,
    otp_uri: *const c_char,
    group: *const c_char,
    expiry_time: i64,
    uuid_out: *mut *mut c_char,
) -> VaultResult {
    if handle.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let title_s = unsafe { cstr_to_str(title) };
        let username_s = unsafe { cstr_to_str(username) };
        let url_s = unsafe { cstr_to_str(url) };
        let notes_s = unsafe { cstr_to_str(notes) };
        let otp_s = unsafe { cstr_to_str(otp_uri) };
        let group_s = unsafe { cstr_to_str(group) };
        let pw = unsafe { read_password(password_ptr, password_len) };

        match state.add_entry_full(title_s, username_s, &pw, url_s, notes_s, otp_s, group_s, expiry_time) {
            Ok(uuid) => {
                if !uuid_out.is_null() {
                    unsafe {
                        *uuid_out = str_to_c(&uuid.to_string());
                    }
                }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_update_entry(
    handle: *mut c_void,
    uuid_str: *const c_char,
    title: *const c_char,
    username: *const c_char,
    password_ptr: *const u8,
    password_len: u32,
    url: *const c_char,
    notes: *const c_char,
    otp_uri: *const c_char,
    expiry_time: i64,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        let title_s = unsafe { cstr_to_str(title) };
        let username_s = unsafe { cstr_to_str(username) };
        let url_s = unsafe { cstr_to_str(url) };
        let notes_s = unsafe { cstr_to_str(notes) };
        let otp_s = unsafe { cstr_to_str(otp_uri) };
        let pw = unsafe { read_password(password_ptr, password_len) };

        match state.update_entry_full(uuid, title_s, username_s, &pw, url_s, notes_s, otp_s, expiry_time) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_delete_entry(
    handle: *mut c_void,
    uuid_str: *const c_char,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        match state.delete_entry(uuid) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// List all group paths in the vault. Returns a null-terminated array of C strings.
/// Free with `group_list_free`.
#[no_mangle]
pub extern "C" fn vault_list_groups(
    handle: *mut c_void,
    groups_out: *mut *mut *mut c_char,
    count_out: *mut u32,
) -> VaultResult {
    if handle.is_null() || groups_out.is_null() || count_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &*(handle as *const VaultState) };
        let groups = state.list_groups();
        let count = groups.len() as u32;
        let ptrs: Vec<*mut c_char> = groups.iter().map(|g| str_to_c(g)).collect();
        let ptr = if ptrs.is_empty() {
            std::ptr::null_mut()
        } else {
            let mut boxed = ptrs.into_boxed_slice();
            let p = boxed.as_mut_ptr();
            std::mem::forget(boxed);
            p
        };
        unsafe {
            *groups_out = ptr;
            *count_out = count;
        }
        VaultResult::Ok
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Free a group list returned by `vault_list_groups`.
#[no_mangle]
pub extern "C" fn group_list_free(groups: *mut *mut c_char, count: u32) {
    if groups.is_null() || count == 0 {
        return;
    }
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let items = Vec::from_raw_parts(groups, count as usize, count as usize);
        for ptr in items {
            free_c_string(ptr);
        }
    }));
}

/// Permanently remove all entries in the Recycle Bin. Returns the number of
/// entries removed via `count_out` (set to 0 if no Recycle Bin exists).
#[no_mangle]
pub extern "C" fn vault_empty_recyclebin(
    handle: *mut c_void,
    count_out: *mut u32,
) -> VaultResult {
    if handle.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        match state.empty_recyclebin() {
            Ok(count) => {
                if !count_out.is_null() {
                    unsafe { *count_out = count as u32; }
                }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// List entries in the Recycle Bin. Returns the same CEntryList structure.
/// Free with `entry_list_free`.
#[no_mangle]
pub extern "C" fn vault_list_recycled_entries(
    handle: *mut c_void,
    list_out: *mut *mut CEntryList,
) -> VaultResult {
    if handle.is_null() || list_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &*(handle as *const VaultState) };
        let summaries = state.list_recycled_entries();

        let count = summaries.len() as u32;
        let items: Vec<CEntryListItem> = summaries
            .iter()
            .map(|s| CEntryListItem {
                uuid: str_to_c(&s.uuid),
                title: str_to_c(&s.title),
                username: str_to_c(&s.username),
                url: str_to_c(&s.url),
                group: str_to_c(&s.group),
                entry_type: str_to_c(&s.entry_type),
                tags: str_to_c(&s.tags),
                expiry_time: s.expiry_time,
                last_modified: s.last_modified,
                is_favorite: s.is_favorite,
                attachment_count: s.attachment_count,
            })
            .collect();

        let items_ptr = if items.is_empty() {
            std::ptr::null_mut()
        } else {
            let mut items = items.into_boxed_slice();
            let ptr = items.as_mut_ptr();
            std::mem::forget(items);
            ptr
        };

        let list = Box::new(CEntryList {
            entries: items_ptr,
            count,
        });
        unsafe {
            *list_out = Box::into_raw(list);
        }
        VaultResult::Ok
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Restore an entry from the Recycle Bin back to the root group.
#[no_mangle]
pub extern "C" fn vault_restore_entry(
    handle: *mut c_void,
    uuid_str: *const c_char,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        match state.restore_entry(uuid) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Permanently delete a single entry from the Recycle Bin.
#[no_mangle]
pub extern "C" fn vault_permanently_delete_entry(
    handle: *mut c_void,
    uuid_str: *const c_char,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        match state.permanently_delete_entry(uuid) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

// ---------------------------------------------------------------------------
// Password history
// ---------------------------------------------------------------------------

/// Get the password history for an entry. Returns a list of (password, timestamp) pairs.
/// Free with `history_list_free`.
#[no_mangle]
pub extern "C" fn vault_get_entry_history(
    handle: *mut c_void,
    uuid_str: *const c_char,
    list_out: *mut *mut CHistoryList,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() || list_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &*(handle as *const VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        match state.get_entry_history(uuid) {
            Ok(items) => {
                let count = items.len() as u32;
                let c_items: Vec<CHistoryItem> = items.iter().map(|i| CHistoryItem {
                    password: str_to_c(&i.password),
                    timestamp: i.timestamp,
                }).collect();
                let items_ptr = if c_items.is_empty() {
                    std::ptr::null_mut()
                } else {
                    let mut boxed = c_items.into_boxed_slice();
                    let ptr = boxed.as_mut_ptr();
                    std::mem::forget(boxed);
                    ptr
                };
                let list = Box::new(CHistoryList { items: items_ptr, count });
                unsafe { *list_out = Box::into_raw(list); }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Free a history list returned by `vault_get_entry_history`.
#[no_mangle]
pub extern "C" fn history_list_free(list: *mut CHistoryList) {
    if list.is_null() { return; }
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let list = Box::from_raw(list);
        if !list.items.is_null() && list.count > 0 {
            let items = Vec::from_raw_parts(list.items, list.count as usize, list.count as usize);
            for item in items {
                free_c_string(item.password);
            }
        }
    }));
}

// ---------------------------------------------------------------------------
// Attachments
// ---------------------------------------------------------------------------

/// List attachments on an entry. Returns a list of (name, size) pairs.
/// Free with `attachment_list_free`.
#[no_mangle]
pub extern "C" fn vault_list_attachments(
    handle: *mut c_void,
    uuid_str: *const c_char,
    list_out: *mut *mut CAttachmentList,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() || list_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &*(handle as *const VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        match state.list_attachments(uuid) {
            Ok(items) => {
                let count = items.len() as u32;
                let c_items: Vec<CAttachmentInfo> = items.iter().map(|(name, size)| CAttachmentInfo {
                    name: str_to_c(name),
                    size: *size as u64,
                }).collect();
                let items_ptr = if c_items.is_empty() {
                    std::ptr::null_mut()
                } else {
                    let mut boxed = c_items.into_boxed_slice();
                    let ptr = boxed.as_mut_ptr();
                    std::mem::forget(boxed);
                    ptr
                };
                let list = Box::new(CAttachmentList { items: items_ptr, count });
                unsafe { *list_out = Box::into_raw(list); }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Get an attachment's raw data by name.
/// Free with `attachment_data_free`.
#[no_mangle]
pub extern "C" fn vault_get_attachment(
    handle: *mut c_void,
    uuid_str: *const c_char,
    name: *const c_char,
    data_out: *mut *mut CAttachmentData,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() || name.is_null() || data_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &*(handle as *const VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        let name_s = unsafe { cstr_to_str(name) };
        match state.get_attachment(uuid, name_s) {
            Ok(data) => {
                let len = data.len() as u64;
                let data_ptr = if data.is_empty() {
                    std::ptr::null_mut()
                } else {
                    let boxed = data.into_boxed_slice();
                    Box::into_raw(boxed) as *mut u8
                };
                let out = Box::new(CAttachmentData { data: data_ptr, len });
                unsafe { *data_out = Box::into_raw(out); }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Add an attachment to an entry.
#[no_mangle]
pub extern "C" fn vault_add_attachment(
    handle: *mut c_void,
    uuid_str: *const c_char,
    name: *const c_char,
    data: *const u8,
    data_len: u64,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() || name.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        let name_s = unsafe { cstr_to_str(name) };
        let slice = if data.is_null() || data_len == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(data, data_len as usize) }
        };
        match state.add_attachment(uuid, name_s, slice) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Remove an attachment from an entry by name.
#[no_mangle]
pub extern "C" fn vault_remove_attachment(
    handle: *mut c_void,
    uuid_str: *const c_char,
    name: *const c_char,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() || name.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        let name_s = unsafe { cstr_to_str(name) };
        match state.remove_attachment(uuid, name_s) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

/// Free an attachment list returned by `vault_list_attachments`.
#[no_mangle]
pub extern "C" fn attachment_list_free(list: *mut CAttachmentList) {
    if list.is_null() { return; }
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let list = Box::from_raw(list);
        if !list.items.is_null() && list.count > 0 {
            let items = Vec::from_raw_parts(list.items, list.count as usize, list.count as usize);
            for item in items {
                free_c_string(item.name);
            }
        }
    }));
}

/// Free attachment data returned by `vault_get_attachment`.
#[no_mangle]
pub extern "C" fn attachment_data_free(data: *mut CAttachmentData) {
    if data.is_null() { return; }
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let data = Box::from_raw(data);
        if !data.data.is_null() && data.len > 0 {
            let raw = std::ptr::slice_from_raw_parts_mut(data.data, data.len as usize);
            drop(Box::from_raw(raw));
        }
    }));
}

// ---------------------------------------------------------------------------
// Favorites & custom fields
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn vault_set_favorite(
    handle: *mut c_void,
    uuid_str: *const c_char,
    favorite: bool,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        match state.set_favorite(uuid, favorite) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_set_custom_field(
    handle: *mut c_void,
    uuid_str: *const c_char,
    key: *const c_char,
    value: *const c_char,
    is_protected: bool,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() || key.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        let key_s = unsafe { cstr_to_str(key) };
        let value_s = unsafe { cstr_to_str(value) };
        match state.set_custom_field(uuid, key_s, value_s, is_protected) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

#[no_mangle]
pub extern "C" fn vault_remove_custom_field(
    handle: *mut c_void,
    uuid_str: *const c_char,
    key: *const c_char,
) -> VaultResult {
    if handle.is_null() || uuid_str.is_null() || key.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let uuid_s = unsafe { cstr_to_str(uuid_str) };
        let uuid = match uuid::Uuid::parse_str(uuid_s) {
            Ok(u) => u,
            Err(_) => return VaultResult::InternalError,
        };
        let key_s = unsafe { cstr_to_str(key) };
        match state.remove_custom_field(uuid, key_s) {
            Ok(()) => VaultResult::Ok,
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

// ---------------------------------------------------------------------------
// Password generation
// ---------------------------------------------------------------------------

/// Generate a random password of `length` bytes into `buf_out`.
///
/// The buffer receives exactly `length` bytes of password data.  If
/// `buf_len > length`, a null terminator is written at `buf_out[length]`
/// so the buffer can be used as a C string.  Callers that need a C string
/// should allocate `length + 1` bytes.
#[no_mangle]
pub extern "C" fn generate_password(
    length: u32,
    charset: u32,
    buf_out: *mut u8,
    buf_len: u32,
) -> VaultResult {
    if buf_out.is_null() || length == 0 || buf_len < length {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        match password::generate(length as usize, charset) {
            Ok(pw) => {
                unsafe {
                    std::ptr::copy_nonoverlapping(pw.as_ptr(), buf_out, pw.len());
                    // Write null terminator if the buffer has room.
                    if buf_len > length {
                        *buf_out.add(length as usize) = 0;
                    }
                }
                VaultResult::Ok
            }
            Err(e) => e,
        }
    }));
    result.unwrap_or(VaultResult::InternalError)
}

// ---------------------------------------------------------------------------
// Memory deallocation
// ---------------------------------------------------------------------------

/// Free a C string that was allocated by the Rust core (e.g. UUID from vault_add_entry).
/// Callers MUST use this instead of their language's native free to avoid cross-allocator UB.
#[no_mangle]
pub extern "C" fn string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        free_c_string(ptr);
    }));
}

#[no_mangle]
pub extern "C" fn entry_list_free(list: *mut CEntryList) {
    if list.is_null() {
        return;
    }
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let list = Box::from_raw(list);
        if !list.entries.is_null() && list.count > 0 {
            let items =
                Vec::from_raw_parts(list.entries, list.count as usize, list.count as usize);
            for item in items {
                free_c_string(item.uuid);
                free_c_string(item.title);
                free_c_string(item.username);
                free_c_string(item.url);
                free_c_string(item.group);
                free_c_string(item.entry_type);
                free_c_string(item.tags);
            }
        }
    }));
}

#[no_mangle]
pub extern "C" fn entry_data_free(data: *mut CEntryData) {
    if data.is_null() {
        return;
    }
    let _ = catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
        let data = Box::from_raw(data);
        // Zeroize password bytes before freeing.  Using the zeroize crate's
        // volatile write ensures LLVM cannot elide this as a dead store.
        if !data.password.is_null() && data.password_len > 0 {
            let raw = std::ptr::slice_from_raw_parts_mut(
                data.password,
                data.password_len as usize,
            );
            (&mut *raw).zeroize();
            drop(Box::from_raw(raw));
        }
        // Free custom fields
        if !data.custom_fields.is_null() && data.custom_field_count > 0 {
            let cfs = Vec::from_raw_parts(
                data.custom_fields,
                data.custom_field_count as usize,
                data.custom_field_count as usize,
            );
            for cf in cfs {
                free_c_string(cf.key);
                free_c_string(cf.value);
            }
        }
        free_c_string(data.uuid);
        free_c_string(data.title);
        free_c_string(data.username);
        free_c_string(data.url);
        free_c_string(data.notes);
        free_c_string(data.otp_uri);
        free_c_string(data.entry_type);
    }));
}
