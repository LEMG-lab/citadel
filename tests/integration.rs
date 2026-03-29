use std::ffi::{CStr, CString};
use std::ptr;

use citadel_core::ffi::*;
use citadel_core::types::*;

/// Helper: open the test fixture.
fn open_fixture() -> *mut std::ffi::c_void {
    let path = format!("{}/test-fixture.kdbx", env!("CARGO_MANIFEST_DIR"));
    let c_path = CString::new(path).unwrap();
    let password = b"Test123";
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_open(
        c_path.as_ptr(),
        password.as_ptr(),
        password.len() as u32,
        ptr::null(),
        &mut handle,
    );
    assert_eq!(result, VaultResult::Ok, "failed to open test fixture");
    assert!(!handle.is_null());
    handle
}

#[test]
fn open_fixture_and_list_entries() {
    let handle = open_fixture();

    let mut list: *mut CEntryList = ptr::null_mut();
    let result = vault_list_entries(handle, &mut list);
    assert_eq!(result, VaultResult::Ok);
    assert!(!list.is_null());

    let list_ref = unsafe { &*list };
    // The fixture should have at least one entry
    assert!(
        list_ref.count > 0,
        "fixture should have entries, got {}",
        list_ref.count
    );

    // Print entries for debugging
    for i in 0..list_ref.count {
        let item = unsafe { &*list_ref.entries.add(i as usize) };
        let title = if item.title.is_null() {
            "(null)"
        } else {
            unsafe { CStr::from_ptr(item.title) }.to_str().unwrap_or("?")
        };
        let uuid = if item.uuid.is_null() {
            "(null)"
        } else {
            unsafe { CStr::from_ptr(item.uuid) }.to_str().unwrap_or("?")
        };
        eprintln!("  entry[{}]: uuid={}, title={}", i, uuid, title);
    }

    entry_list_free(list);
    vault_close(handle);
}

#[test]
fn open_fixture_and_read_entry() {
    let handle = open_fixture();

    // First, list to get a UUID
    let mut list: *mut CEntryList = ptr::null_mut();
    assert_eq!(vault_list_entries(handle, &mut list), VaultResult::Ok);
    let list_ref = unsafe { &*list };
    assert!(list_ref.count > 0);

    let first_uuid = unsafe { CStr::from_ptr((*list_ref.entries).uuid) }
        .to_str()
        .unwrap();
    let uuid_cstr = CString::new(first_uuid).unwrap();

    // Now get the full entry
    let mut entry: *mut CEntryData = ptr::null_mut();
    let result = vault_get_entry(handle, uuid_cstr.as_ptr(), &mut entry);
    assert_eq!(result, VaultResult::Ok);
    assert!(!entry.is_null());

    let entry_ref = unsafe { &*entry };
    assert!(!entry_ref.password.is_null(), "password should be present");
    assert!(entry_ref.password_len > 0, "password should not be empty");

    let password = unsafe {
        std::slice::from_raw_parts(entry_ref.password, entry_ref.password_len as usize)
    };
    eprintln!("  entry password length: {}", password.len());

    entry_data_free(entry);
    entry_list_free(list);
    vault_close(handle);
}

#[test]
fn wrong_password_on_fixture() {
    let path = format!("{}/test-fixture.kdbx", env!("CARGO_MANIFEST_DIR"));
    let c_path = CString::new(path).unwrap();
    let wrong_pw = b"wrong-password";
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_open(
        c_path.as_ptr(),
        wrong_pw.as_ptr(),
        wrong_pw.len() as u32,
        ptr::null(),
        &mut handle,
    );
    assert_eq!(result, VaultResult::WrongPassword);
}

#[test]
fn validate_fixture() {
    let path = format!("{}/test-fixture.kdbx", env!("CARGO_MANIFEST_DIR"));
    let c_path = CString::new(path).unwrap();

    let good_pw = b"Test123";
    assert_eq!(
        vault_validate(c_path.as_ptr(), good_pw.as_ptr(), good_pw.len() as u32, ptr::null()),
        VaultResult::Ok
    );

    let bad_pw = b"nope";
    assert_eq!(
        vault_validate(c_path.as_ptr(), bad_pw.as_ptr(), bad_pw.len() as u32, ptr::null()),
        VaultResult::WrongPassword
    );
}

#[test]
fn full_crud_lifecycle() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let path = tmp.path().to_str().unwrap();
    let c_path = CString::new(path).unwrap();
    let password = b"lifecycle-test";

    // Create vault (in-memory only; save comes later)
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    assert_eq!(
        vault_create(
            password.as_ptr(),
            password.len() as u32,
            ptr::null(),
            &mut handle,
        ),
        VaultResult::Ok
    );
    assert!(!handle.is_null());

    // Add entry
    let title = CString::new("Test Entry").unwrap();
    let username = CString::new("testuser").unwrap();
    let entry_pw = b"entry-password";
    let url = CString::new("https://example.com").unwrap();
    let notes = CString::new("some notes").unwrap();
    let mut uuid_ptr: *mut std::ffi::c_char = ptr::null_mut();

    assert_eq!(
        vault_add_entry(
            handle,
            title.as_ptr(),
            username.as_ptr(),
            entry_pw.as_ptr(),
            entry_pw.len() as u32,
            url.as_ptr(),
            notes.as_ptr(),
            &mut uuid_ptr,
        ),
        VaultResult::Ok
    );
    assert!(!uuid_ptr.is_null());
    let uuid_string = unsafe { CStr::from_ptr(uuid_ptr) }
        .to_str()
        .unwrap()
        .to_string();

    // Save
    assert_eq!(vault_save_to(handle, c_path.as_ptr()), VaultResult::Ok);

    // List entries — should have 1
    let mut list: *mut CEntryList = ptr::null_mut();
    assert_eq!(vault_list_entries(handle, &mut list), VaultResult::Ok);
    assert_eq!(unsafe { (*list).count }, 1);
    entry_list_free(list);

    // Get entry
    let uuid_cstr = CString::new(uuid_string.as_str()).unwrap();
    let mut entry: *mut CEntryData = ptr::null_mut();
    assert_eq!(
        vault_get_entry(handle, uuid_cstr.as_ptr(), &mut entry),
        VaultResult::Ok
    );
    let entry_ref = unsafe { &*entry };
    assert_eq!(
        unsafe { CStr::from_ptr(entry_ref.title) }.to_str().unwrap(),
        "Test Entry"
    );
    assert_eq!(
        unsafe { std::slice::from_raw_parts(entry_ref.password, entry_ref.password_len as usize) },
        b"entry-password"
    );
    entry_data_free(entry);

    // Update entry
    let new_title = CString::new("Updated Entry").unwrap();
    let new_pw = b"new-password";
    assert_eq!(
        vault_update_entry(
            handle,
            uuid_cstr.as_ptr(),
            new_title.as_ptr(),
            username.as_ptr(),
            new_pw.as_ptr(),
            new_pw.len() as u32,
            url.as_ptr(),
            notes.as_ptr(),
        ),
        VaultResult::Ok
    );

    // Verify update
    let mut entry2: *mut CEntryData = ptr::null_mut();
    assert_eq!(
        vault_get_entry(handle, uuid_cstr.as_ptr(), &mut entry2),
        VaultResult::Ok
    );
    let entry2_ref = unsafe { &*entry2 };
    assert_eq!(
        unsafe { CStr::from_ptr(entry2_ref.title) }
            .to_str()
            .unwrap(),
        "Updated Entry"
    );
    assert_eq!(
        unsafe { std::slice::from_raw_parts(entry2_ref.password, entry2_ref.password_len as usize) },
        b"new-password"
    );
    entry_data_free(entry2);

    // Delete entry
    assert_eq!(
        vault_delete_entry(handle, uuid_cstr.as_ptr()),
        VaultResult::Ok
    );
    let mut list2: *mut CEntryList = ptr::null_mut();
    assert_eq!(vault_list_entries(handle, &mut list2), VaultResult::Ok);
    assert_eq!(unsafe { (*list2).count }, 0);
    entry_list_free(list2);

    // Change password and re-save
    let new_vault_pw = b"new-vault-password";
    assert_eq!(
        vault_change_password(handle, new_vault_pw.as_ptr(), new_vault_pw.len() as u32, ptr::null()),
        VaultResult::Ok
    );
    assert_eq!(vault_save_to(handle, c_path.as_ptr()), VaultResult::Ok);

    vault_close(handle);

    // Re-open with new password
    let mut handle2: *mut std::ffi::c_void = ptr::null_mut();
    assert_eq!(
        vault_open(
            c_path.as_ptr(),
            new_vault_pw.as_ptr(),
            new_vault_pw.len() as u32,
            ptr::null(),
            &mut handle2,
        ),
        VaultResult::Ok
    );
    vault_close(handle2);

    // Old password should fail
    let mut handle3: *mut std::ffi::c_void = ptr::null_mut();
    assert_eq!(
        vault_open(
            c_path.as_ptr(),
            password.as_ptr(),
            password.len() as u32,
            ptr::null(),
            &mut handle3,
        ),
        VaultResult::WrongPassword
    );

    // Free the UUID string via Rust's allocator
    string_free(uuid_ptr);
}

#[test]
fn generate_password_ffi() {
    let mut buf = [0u8; 64];
    let result = generate_password(
        32,
        CharsetFlags::LOWERCASE | CharsetFlags::UPPERCASE | CharsetFlags::DIGITS,
        buf.as_mut_ptr(),
        buf.len() as u32,
    );
    assert_eq!(result, VaultResult::Ok);

    let pw = std::str::from_utf8(&buf[..32]).unwrap();
    assert_eq!(pw.len(), 32);
    assert!(pw.chars().all(|c| c.is_ascii_alphanumeric()));
}

#[test]
fn generate_password_buffer_too_small() {
    let mut buf = [0u8; 4];
    let result = generate_password(32, CharsetFlags::LOWERCASE, buf.as_mut_ptr(), buf.len() as u32);
    assert_eq!(result, VaultResult::InternalError);
}
