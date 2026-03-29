//! Negative corpus tests: verify safe handling of malformed, truncated,
//! corrupted, and otherwise invalid KDBX inputs.
//!
//! Every test must:
//! 1. Return an appropriate VaultResult error code
//! 2. NOT panic
//! 3. NOT corrupt any existing files

use std::ffi::CString;
use std::io::{Read, Write};
use std::ptr;

use citadel_core::ffi::*;
use citadel_core::types::*;
use citadel_core::vault::VaultState;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn fixture_path() -> String {
    format!("{}/test-fixture.kdbx", env!("CARGO_MANIFEST_DIR"))
}

fn fixture_bytes() -> Vec<u8> {
    let mut f = std::fs::File::open(fixture_path()).unwrap();
    let mut buf = Vec::new();
    f.read_to_end(&mut buf).unwrap();
    buf
}

/// Write bytes to a temp file and return its path.
fn write_temp(data: &[u8]) -> tempfile::NamedTempFile {
    let mut tmp = tempfile::NamedTempFile::new().unwrap();
    tmp.write_all(data).unwrap();
    tmp.flush().unwrap();
    tmp
}

/// Try to open via FFI, returning the result code.
fn ffi_open_result(path: &str, password: &[u8]) -> VaultResult {
    let c_path = CString::new(path).unwrap();
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_open(
        c_path.as_ptr(),
        password.as_ptr(),
        password.len() as u32,
        &mut handle,
    );
    if result == VaultResult::Ok && !handle.is_null() {
        vault_close(handle);
    }
    result
}

// ===========================================================================
// 1. Zero-byte file
// ===========================================================================

#[test]
fn neg_01_zero_byte_file() {
    let tmp = write_temp(b"");
    let path = tmp.path().to_str().unwrap();

    let err = VaultState::open(path, b"Test123").unwrap_err();
    assert_ne!(err, VaultResult::Ok, "should fail on empty file");

    // FFI path
    let result = ffi_open_result(path, b"Test123");
    assert_ne!(result, VaultResult::Ok);
}

// ===========================================================================
// 2. Random bytes (1 KB)
// ===========================================================================

#[test]
fn neg_02_random_bytes() {
    let data: Vec<u8> = (0..1024).map(|i| (i * 7 + 13) as u8).collect();
    let tmp = write_temp(&data);
    let path = tmp.path().to_str().unwrap();

    let err = VaultState::open(path, b"Test123").unwrap_err();
    assert_ne!(err, VaultResult::Ok);

    let result = ffi_open_result(path, b"Test123");
    assert_ne!(result, VaultResult::Ok);
}

// ===========================================================================
// 3. Valid KDBX magic bytes, truncated after 64 bytes
// ===========================================================================

#[test]
fn neg_03_truncated_after_magic() {
    let full = fixture_bytes();
    assert!(full.len() > 64, "fixture too small");
    let truncated = &full[..64];
    let tmp = write_temp(truncated);
    let path = tmp.path().to_str().unwrap();

    let err = VaultState::open(path, b"Test123").unwrap_err();
    assert_ne!(err, VaultResult::Ok);

    let result = ffi_open_result(path, b"Test123");
    assert_ne!(result, VaultResult::Ok);
}

// ===========================================================================
// 4. Valid KDBX with 1 bit flipped in the middle
// ===========================================================================

#[test]
fn neg_04_single_bit_flip() {
    let mut data = fixture_bytes();
    let mid = data.len() / 2;
    data[mid] ^= 0x01; // flip lowest bit
    let tmp = write_temp(&data);
    let path = tmp.path().to_str().unwrap();

    let err = VaultState::open(path, b"Test123").unwrap_err();
    assert_ne!(err, VaultResult::Ok);

    let result = ffi_open_result(path, b"Test123");
    assert_ne!(result, VaultResult::Ok);
}

// ===========================================================================
// 5. Valid KDBX with last 100 bytes zeroed
// ===========================================================================

#[test]
fn neg_05_zeroed_tail() {
    let mut data = fixture_bytes();
    assert!(data.len() > 100);
    let start = data.len() - 100;
    for b in &mut data[start..] {
        *b = 0;
    }
    let tmp = write_temp(&data);
    let path = tmp.path().to_str().unwrap();

    let err = VaultState::open(path, b"Test123").unwrap_err();
    assert_ne!(err, VaultResult::Ok);

    let result = ffi_open_result(path, b"Test123");
    assert_ne!(result, VaultResult::Ok);
}

// ===========================================================================
// 6. Correct file, wrong password → WrongPassword (not crash)
// ===========================================================================

#[test]
fn neg_06_wrong_password() {
    let path = fixture_path();

    let err = VaultState::open(&path, b"totally-wrong-password").unwrap_err();
    assert_eq!(err, VaultResult::WrongPassword);

    let result = ffi_open_result(&path, b"totally-wrong-password");
    assert_eq!(result, VaultResult::WrongPassword);
}

// ===========================================================================
// 7. Path that doesn't exist → FileNotFound
// ===========================================================================

#[test]
fn neg_07_nonexistent_path() {
    let path = "/tmp/citadel_neg_test_nonexistent_deadbeef.kdbx";
    // Ensure it really doesn't exist
    let _ = std::fs::remove_file(path);

    let err = VaultState::open(path, b"Test123").unwrap_err();
    assert_eq!(err, VaultResult::FileNotFound);

    let result = ffi_open_result(path, b"Test123");
    assert_eq!(result, VaultResult::FileNotFound);
}

// ===========================================================================
// 8. Path is a directory, not a file
// ===========================================================================

#[test]
fn neg_08_directory_path() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().to_str().unwrap();

    let err = VaultState::open(path, b"Test123").unwrap_err();
    assert_ne!(err, VaultResult::Ok);

    let result = ffi_open_result(path, b"Test123");
    assert_ne!(result, VaultResult::Ok);
}

// ===========================================================================
// 9. Empty string path
// ===========================================================================

#[test]
fn neg_09_empty_path() {
    let err = VaultState::open("", b"Test123").unwrap_err();
    assert_ne!(err, VaultResult::Ok);

    // FFI: empty C string (just a null terminator)
    let c_path = CString::new("").unwrap();
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_open(
        c_path.as_ptr(),
        b"Test123".as_ptr(),
        7,
        &mut handle,
    );
    assert_ne!(result, VaultResult::Ok);
    if result == VaultResult::Ok && !handle.is_null() {
        vault_close(handle);
    }
}

// ===========================================================================
// 10. Valid KDBX header but garbage payload
// ===========================================================================

#[test]
fn neg_10_valid_header_garbage_payload() {
    let full = fixture_bytes();
    // KDBX4 header ends around byte 200-300 typically.
    // Keep first 256 bytes (header region), replace rest with garbage.
    let header_len = 256.min(full.len());
    let mut data = full[..header_len].to_vec();
    let garbage: Vec<u8> = (0..1024).map(|i| ((i * 37 + 99) % 256) as u8).collect();
    data.extend_from_slice(&garbage);

    let tmp = write_temp(&data);
    let path = tmp.path().to_str().unwrap();

    let err = VaultState::open(path, b"Test123").unwrap_err();
    assert_ne!(err, VaultResult::Ok);

    let result = ffi_open_result(path, b"Test123");
    assert_ne!(result, VaultResult::Ok);
}

// ===========================================================================
// Bonus: verify no existing file corruption
// ===========================================================================

#[test]
fn neg_11_fixture_unchanged_after_all_negative_tests() {
    // Re-read the fixture and verify it can still be opened correctly.
    let path = fixture_path();
    let state = VaultState::open(&path, b"Test123").expect("fixture should still be openable");
    let entries = state.list_entries();
    assert_eq!(entries.len(), 3, "fixture should still have 3 entries");
}
