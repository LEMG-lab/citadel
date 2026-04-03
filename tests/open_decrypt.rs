//! Regression test: verify KDBX open/decrypt works for password "Abc123".
//!
//! Tests both the keepass-rs Database layer directly and the citadel FFI layer
//! to isolate where a decryption failure originates.

use std::ffi::CString;
use std::ptr;

use citadel_core::ffi::*;
use citadel_core::types::*;
use keepass::{Database, DatabaseKey};

/// Create a vault with "Abc123" via FFI, save to disk, then reopen via FFI.
#[test]
fn ffi_roundtrip_abc123() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let path = tmp.path().to_str().unwrap();
    let c_path = CString::new(path).unwrap();
    let password = b"Abc123";

    // Create
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_create(
        password.as_ptr(),
        password.len() as u32,
        ptr::null(),
        &mut handle,
    );
    assert_eq!(result, VaultResult::Ok, "vault_create failed");

    // Add an entry so it's not empty
    let title = CString::new("TestEntry").unwrap();
    let user = CString::new("user@test.com").unwrap();
    let epw = b"entry-pw";
    let url = CString::new("https://example.com").unwrap();
    let notes = CString::new("").unwrap();
    let mut uuid_ptr: *mut std::ffi::c_char = ptr::null_mut();
    assert_eq!(
        vault_add_entry(
            handle,
            title.as_ptr(),
            user.as_ptr(),
            epw.as_ptr(),
            epw.len() as u32,
            url.as_ptr(),
            notes.as_ptr(),
            ptr::null(),
            ptr::null(),
            0,
            &mut uuid_ptr,
        ),
        VaultResult::Ok,
    );
    string_free(uuid_ptr);

    // Save
    assert_eq!(vault_save_to(handle, c_path.as_ptr()), VaultResult::Ok);
    vault_close(handle);

    // Reopen with same password via FFI
    let mut handle2: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_open(
        c_path.as_ptr(),
        password.as_ptr(),
        password.len() as u32,
        ptr::null(),
        &mut handle2,
    );
    assert_eq!(
        result,
        VaultResult::Ok,
        "vault_open with 'Abc123' failed — decrypt regression"
    );
    assert!(!handle2.is_null());

    // Verify the entry survived
    let mut list: *mut CEntryList = ptr::null_mut();
    assert_eq!(vault_list_entries(handle2, &mut list), VaultResult::Ok);
    assert_eq!(unsafe { (*list).count }, 1);
    entry_list_free(list);

    vault_close(handle2);
}

/// Create a vault with "Abc123" via FFI, save, then reopen with keepass-rs
/// Database::open directly — bypasses FFI to isolate the decrypt layer.
#[test]
fn keepass_rs_direct_open_abc123() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let path = tmp.path().to_str().unwrap();
    let c_path = CString::new(path).unwrap();
    let password = b"Abc123";

    // Create and save via FFI (known working path for creating)
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    assert_eq!(
        vault_create(
            password.as_ptr(),
            password.len() as u32,
            ptr::null(),
            &mut handle,
        ),
        VaultResult::Ok,
    );
    assert_eq!(vault_save_to(handle, c_path.as_ptr()), VaultResult::Ok);
    vault_close(handle);

    // Now open directly with keepass-rs
    let mut file = std::fs::File::open(path).expect("saved file should exist");
    let key = DatabaseKey::new().with_password("Abc123");
    let db = Database::open(&mut file, key);
    assert!(
        db.is_ok(),
        "keepass-rs Database::open failed for 'Abc123': {:?}",
        db.err()
    );
}

/// Verify that a wrong password is correctly rejected (not a false positive).
#[test]
fn ffi_wrong_password_rejected() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let path = tmp.path().to_str().unwrap();
    let c_path = CString::new(path).unwrap();
    let password = b"Abc123";

    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    assert_eq!(
        vault_create(
            password.as_ptr(),
            password.len() as u32,
            ptr::null(),
            &mut handle,
        ),
        VaultResult::Ok,
    );
    assert_eq!(vault_save_to(handle, c_path.as_ptr()), VaultResult::Ok);
    vault_close(handle);

    // Wrong password must fail
    let wrong = b"wrong";
    let mut handle2: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_open(
        c_path.as_ptr(),
        wrong.as_ptr(),
        wrong.len() as u32,
        ptr::null(),
        &mut handle2,
    );
    assert_eq!(result, VaultResult::WrongPassword);
}

/// Open the test-fixture.kdbx with its known password to confirm the existing
/// fixture still works (baseline sanity check).
#[test]
fn fixture_still_opens() {
    let path = format!("{}/test-fixture.kdbx", env!("CARGO_MANIFEST_DIR"));
    let c_path = CString::new(path.as_str()).unwrap();
    let password = b"Test123";

    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_open(
        c_path.as_ptr(),
        password.as_ptr(),
        password.len() as u32,
        ptr::null(),
        &mut handle,
    );
    assert_eq!(
        result,
        VaultResult::Ok,
        "test-fixture.kdbx should open with 'Test123'"
    );
    vault_close(handle);
}
