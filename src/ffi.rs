use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::catch_unwind;
use std::slice;
use zeroize::{Zeroize, Zeroizing};

use crate::password;
use crate::types::*;
use crate::vault::VaultState;

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
    handle_out: *mut *mut c_void,
) -> VaultResult {
    if path.is_null() || handle_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let path_str = unsafe { cstr_to_str(path) };
        let pw = unsafe { read_password(password_ptr, password_len) };
        match VaultState::open(path_str, &pw) {
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
    handle_out: *mut *mut c_void,
) -> VaultResult {
    if handle_out.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let pw = unsafe { read_password(password_ptr, password_len) };
        match VaultState::create(&pw) {
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
) -> VaultResult {
    if path.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let path_str = unsafe { cstr_to_str(path) };
        let pw = unsafe { read_password(password_ptr, password_len) };
        match VaultState::validate(path_str, &pw) {
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
) -> VaultResult {
    if handle.is_null() {
        return VaultResult::InternalError;
    }
    let result = catch_unwind(std::panic::AssertUnwindSafe(|| {
        let state = unsafe { &mut *(handle as *mut VaultState) };
        let pw = unsafe { read_password(new_password_ptr, new_password_len) };
        match state.change_password(&pw) {
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
                let data = Box::new(CEntryData {
                    uuid: str_to_c(&detail.uuid),
                    title: str_to_c(&detail.title),
                    username: str_to_c(&detail.username),
                    password: pw_ptr,
                    password_len: pw_len,
                    url: str_to_c(&detail.url),
                    notes: str_to_c(&detail.notes),
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
        let pw = unsafe { read_password(password_ptr, password_len) };

        match state.add_entry(title_s, username_s, &pw, url_s, notes_s) {
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
        let pw = unsafe { read_password(password_ptr, password_len) };

        match state.update_entry(uuid, title_s, username_s, &pw, url_s, notes_s) {
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
        free_c_string(data.uuid);
        free_c_string(data.title);
        free_c_string(data.username);
        free_c_string(data.url);
        free_c_string(data.notes);
    }));
}
