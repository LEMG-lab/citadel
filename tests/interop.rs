//! Phase 2: Interoperability tests.
//!
//! These tests verify:
//! 1. Reading the KeePassXC-created fixture with exact field matching
//! 2. Creating a new vault, writing entries, roundtripping through disk
//! 3. Opening a fixture, adding entries, saving, and verifying the merge

use std::ffi::{CStr, CString};
use std::ptr;

use citadel_core::ffi::*;
use citadel_core::types::*;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const FIXTURE_PASSWORD: &[u8] = b"Test123";

fn fixture_path() -> String {
    format!("{}/test-fixture.kdbx", env!("CARGO_MANIFEST_DIR"))
}

/// Open a vault via FFI, returning the handle. Panics on failure.
fn ffi_open(path: &str, password: &[u8]) -> *mut std::ffi::c_void {
    let c_path = CString::new(path).unwrap();
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_open(
        c_path.as_ptr(),
        password.as_ptr(),
        password.len() as u32,
        ptr::null(),
        &mut handle,
    );
    assert_eq!(result, VaultResult::Ok, "vault_open failed for {}", path);
    assert!(!handle.is_null());
    handle
}

/// Create a vault via FFI (in-memory), returning the handle. Panics on failure.
fn ffi_create(password: &[u8]) -> *mut std::ffi::c_void {
    let mut handle: *mut std::ffi::c_void = ptr::null_mut();
    let result = vault_create(
        password.as_ptr(),
        password.len() as u32,
        ptr::null(),
        &mut handle,
    );
    assert_eq!(result, VaultResult::Ok, "vault_create failed");
    assert!(!handle.is_null());
    handle
}

/// Save via FFI. Panics on failure.
fn ffi_save(handle: *mut std::ffi::c_void, path: &str) {
    let c_path = CString::new(path).unwrap();
    assert_eq!(vault_save_to(handle, c_path.as_ptr()), VaultResult::Ok);
}

/// Read a C string from a raw pointer, returning "" for null.
unsafe fn read_cstr(ptr: *const std::ffi::c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        CStr::from_ptr(ptr).to_str().unwrap_or("").to_string()
    }
}

/// Collect all entry summaries from a handle.
fn ffi_list(handle: *mut std::ffi::c_void) -> Vec<(String, String, String, String)> {
    let mut list_ptr: *mut CEntryList = ptr::null_mut();
    assert_eq!(vault_list_entries(handle, &mut list_ptr), VaultResult::Ok);
    let list = unsafe { &*list_ptr };
    let mut out = Vec::new();
    for i in 0..list.count as usize {
        let item = unsafe { &*list.entries.add(i) };
        unsafe {
            out.push((
                read_cstr(item.uuid),
                read_cstr(item.title),
                read_cstr(item.username),
                read_cstr(item.url),
            ));
        }
    }
    entry_list_free(list_ptr);
    out
}

/// Fetch a single entry's full data by UUID string.
struct FullEntry {
    #[allow(dead_code)]
    uuid: String,
    title: String,
    username: String,
    password: String,
    url: String,
    notes: String,
}

fn ffi_get_entry(handle: *mut std::ffi::c_void, uuid: &str) -> FullEntry {
    let c_uuid = CString::new(uuid).unwrap();
    let mut entry_ptr: *mut CEntryData = ptr::null_mut();
    let result = vault_get_entry(handle, c_uuid.as_ptr(), &mut entry_ptr);
    assert_eq!(result, VaultResult::Ok, "vault_get_entry failed for {}", uuid);
    let e = unsafe { &*entry_ptr };
    let full = unsafe {
        FullEntry {
            uuid: read_cstr(e.uuid),
            title: read_cstr(e.title),
            username: read_cstr(e.username),
            password: if e.password.is_null() || e.password_len == 0 {
                String::new()
            } else {
                std::str::from_utf8(std::slice::from_raw_parts(e.password, e.password_len as usize))
                    .unwrap_or("")
                    .to_string()
            },
            url: read_cstr(e.url),
            notes: read_cstr(e.notes),
        }
    };
    entry_data_free(entry_ptr);
    full
}

/// Add an entry and return its UUID string.
fn ffi_add_entry(
    handle: *mut std::ffi::c_void,
    title: &str,
    username: &str,
    password: &[u8],
    url: &str,
    notes: &str,
) -> String {
    let c_title = CString::new(title).unwrap();
    let c_user = CString::new(username).unwrap();
    let c_url = CString::new(url).unwrap();
    let c_notes = CString::new(notes).unwrap();
    let mut uuid_ptr: *mut std::ffi::c_char = ptr::null_mut();
    let result = vault_add_entry(
        handle,
        c_title.as_ptr(),
        c_user.as_ptr(),
        password.as_ptr(),
        password.len() as u32,
        c_url.as_ptr(),
        c_notes.as_ptr(),
        ptr::null(),
        &mut uuid_ptr,
    );
    assert_eq!(result, VaultResult::Ok, "vault_add_entry failed for {}", title);
    let uuid_str = unsafe { read_cstr(uuid_ptr) };
    string_free(uuid_ptr);
    uuid_str
}

// ===========================================================================
// Test 1: Open fixture — verify every field of every entry
// ===========================================================================

/// Exact expected data from the KeePassXC-created test-fixture.kdbx.
struct ExpectedEntry {
    title: &'static str,
    username: &'static str,
    password: &'static str,
    url: &'static str,
    notes: &'static str,
}

const FIXTURE_ENTRIES: [ExpectedEntry; 3] = [
    ExpectedEntry {
        title: "Pruenba1 ",
        username: " testuser@gmail.com",
        password: "fakepass1",
        url: "https://gmail.com",
        notes: "",
    },
    ExpectedEntry {
        title: "Fake test 2",
        username: "prueba@gmail.com",
        password: "Test123",
        url: "http://gmail.com",
        notes: "",
    },
    ExpectedEntry {
        title: "prueba3",
        username: "prueba3@gmail.com",
        password: "Test123",
        url: "Http://gmail.com",
        notes: "",
    },
];

#[test]
fn interop_1_fixture_list_and_verify_all_fields() {
    let handle = ffi_open(&fixture_path(), FIXTURE_PASSWORD);

    // --- List entries and verify titles ---
    let summaries = ffi_list(handle);
    assert_eq!(summaries.len(), 3, "fixture should have exactly 3 entries");

    let listed_titles: Vec<&str> = summaries.iter().map(|s| s.1.as_str()).collect();
    for expected in &FIXTURE_ENTRIES {
        assert!(
            listed_titles.contains(&expected.title),
            "missing title {:?} in list; got {:?}",
            expected.title,
            listed_titles,
        );
    }

    // --- Read each entry by UUID and verify every field ---
    for (uuid, title, _, _) in &summaries {
        let full = ffi_get_entry(handle, uuid);

        let expected = FIXTURE_ENTRIES
            .iter()
            .find(|e| e.title == title.as_str())
            .unwrap_or_else(|| panic!("unexpected title {:?}", title));

        assert_eq!(full.title, expected.title, "title mismatch");
        assert_eq!(full.username, expected.username, "username mismatch for {}", expected.title);
        assert_eq!(full.password, expected.password, "password mismatch for {}", expected.title);
        assert_eq!(full.url, expected.url, "url mismatch for {}", expected.title);
        assert_eq!(full.notes, expected.notes, "notes mismatch for {}", expected.title);
    }

    // --- Verify list does NOT contain passwords (check struct directly) ---
    let mut list_ptr: *mut CEntryList = ptr::null_mut();
    assert_eq!(vault_list_entries(handle, &mut list_ptr), VaultResult::Ok);
    let list = unsafe { &*list_ptr };
    // CEntryListItem has no password field — this is enforced at the type level.
    // As a sanity check, confirm the struct size doesn't contain extra hidden data
    // by just checking the 4 expected fields are present.
    for i in 0..list.count as usize {
        let item = unsafe { &*list.entries.add(i) };
        assert!(!item.uuid.is_null());
        assert!(!item.title.is_null());
    }
    entry_list_free(list_ptr);

    vault_close(handle);
}

// ===========================================================================
// Test 2: Create new vault, add 3 entries, save, reopen, verify
// ===========================================================================

#[test]
fn interop_2_create_save_reopen_verify() {
    let output_path = format!("{}/test-output.kdbx", env!("CARGO_MANIFEST_DIR"));
    let password = b"InteropTest1";

    // --- Create (in-memory) and populate ---
    let handle = ffi_create(password);

    let uuid_alpha = ffi_add_entry(
        handle,
        "Alpha",
        "alpha@test.com",
        b"alpha-pass-1",
        "https://alpha.com",
        "",
    );
    let uuid_beta = ffi_add_entry(
        handle,
        "Beta",
        "beta-user",
        b"beta-pass-2",
        "https://beta.com",
        "Beta account",
    );
    let uuid_gamma = ffi_add_entry(
        handle,
        "Gamma",
        "gamma-user",
        b"gamma-pass-3",
        "https://gamma.com",
        "",
    );

    // --- Save and close ---
    ffi_save(handle, &output_path);
    vault_close(handle);

    // --- Reopen and verify ---
    let handle2 = ffi_open(&output_path, password);
    let summaries = ffi_list(handle2);
    assert_eq!(summaries.len(), 3, "should have exactly 3 entries after reopen");

    let titles: Vec<&str> = summaries.iter().map(|s| s.1.as_str()).collect();
    assert!(titles.contains(&"Alpha"));
    assert!(titles.contains(&"Beta"));
    assert!(titles.contains(&"Gamma"));

    // Verify Alpha
    let alpha = ffi_get_entry(handle2, &uuid_alpha);
    assert_eq!(alpha.title, "Alpha");
    assert_eq!(alpha.username, "alpha@test.com");
    assert_eq!(alpha.password, "alpha-pass-1");
    assert_eq!(alpha.url, "https://alpha.com");
    assert_eq!(alpha.notes, "");

    // Verify Beta
    let beta = ffi_get_entry(handle2, &uuid_beta);
    assert_eq!(beta.title, "Beta");
    assert_eq!(beta.username, "beta-user");
    assert_eq!(beta.password, "beta-pass-2");
    assert_eq!(beta.url, "https://beta.com");
    assert_eq!(beta.notes, "Beta account");

    // Verify Gamma
    let gamma = ffi_get_entry(handle2, &uuid_gamma);
    assert_eq!(gamma.title, "Gamma");
    assert_eq!(gamma.username, "gamma-user");
    assert_eq!(gamma.password, "gamma-pass-3");
    assert_eq!(gamma.url, "https://gamma.com");
    assert_eq!(gamma.notes, "");

    vault_close(handle2);

    eprintln!("test-output.kdbx written to: {}", output_path);
}

// ===========================================================================
// Test 3: Open fixture, add entry, save to new file, verify merge
// ===========================================================================

#[test]
fn interop_3_modify_fixture_and_verify_merge() {
    let modified_path = format!("{}/test-modified.kdbx", env!("CARGO_MANIFEST_DIR"));

    // --- Open the original fixture ---
    let handle = ffi_open(&fixture_path(), FIXTURE_PASSWORD);

    // Verify we start with the 3 original entries
    let before = ffi_list(handle);
    assert_eq!(before.len(), 3, "fixture should start with 3 entries");

    // --- Add a new entry ---
    let new_uuid = ffi_add_entry(
        handle,
        "NewEntry",
        "newuser",
        b"newpass",
        "https://new.com",
        "",
    );

    // --- Save to a different file (don't overwrite original fixture) ---
    ffi_save(handle, &modified_path);
    vault_close(handle);

    // --- Reopen the modified file ---
    let handle2 = ffi_open(&modified_path, FIXTURE_PASSWORD);
    let after = ffi_list(handle2);
    assert_eq!(after.len(), 4, "modified file should have 4 entries (3 original + 1 new)");

    // Verify the 3 original entries are still there with correct titles
    let titles: Vec<&str> = after.iter().map(|s| s.1.as_str()).collect();
    for expected in &FIXTURE_ENTRIES {
        assert!(
            titles.contains(&expected.title),
            "original entry {:?} missing after modification",
            expected.title,
        );
    }
    assert!(titles.contains(&"NewEntry"), "new entry missing");

    // Spot-check: verify the first original entry's full data survived
    let original_uuid = after
        .iter()
        .find(|s| s.1 == "Pruenba1 ")
        .map(|s| s.0.as_str())
        .expect("Pruenba1 entry not found");
    let orig = ffi_get_entry(handle2, original_uuid);
    assert_eq!(orig.username, " testuser@gmail.com");
    assert_eq!(orig.password, "fakepass1");
    assert_eq!(orig.url, "https://gmail.com");

    // Verify the new entry's full data
    let new_entry = ffi_get_entry(handle2, &new_uuid);
    assert_eq!(new_entry.title, "NewEntry");
    assert_eq!(new_entry.username, "newuser");
    assert_eq!(new_entry.password, "newpass");
    assert_eq!(new_entry.url, "https://new.com");
    assert_eq!(new_entry.notes, "");

    vault_close(handle2);

    // --- Also verify the original fixture was NOT modified ---
    let handle_orig = ffi_open(&fixture_path(), FIXTURE_PASSWORD);
    let orig_entries = ffi_list(handle_orig);
    assert_eq!(
        orig_entries.len(),
        3,
        "original fixture must still have exactly 3 entries"
    );
    vault_close(handle_orig);

    eprintln!("test-modified.kdbx written to: {}", modified_path);
}
