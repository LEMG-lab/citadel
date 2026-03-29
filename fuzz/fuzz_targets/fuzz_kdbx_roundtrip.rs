#![no_main]

use libfuzzer_sys::fuzz_target;

const FIXTURE_PASSWORD: &[u8] = b"Test123";

fuzz_target!(|data: &[u8]| {
    // Need at least 3 bytes to split into field selector + 2 content chunks
    if data.len() < 3 {
        return;
    }

    let fixture_path = concat!(env!("CARGO_MANIFEST_DIR"), "/../test-fixture.kdbx");

    // Open the real fixture
    let mut state = match citadel_core::vault::VaultState::open(fixture_path, FIXTURE_PASSWORD) {
        Ok(s) => s,
        Err(_) => return,
    };

    let entries = state.list_entries();
    if entries.is_empty() {
        return;
    }

    // Pick an entry to mutate using first byte
    let entry_idx = data[0] as usize % entries.len();
    let uuid = match uuid::Uuid::parse_str(&entries[entry_idx].uuid) {
        Ok(u) => u,
        Err(_) => return,
    };

    // Use second byte to pick which field to mutate
    let field_selector = data[1] % 5;

    // Use remaining bytes as the fuzz content
    let fuzz_content = &data[2..];

    // Attempt to interpret fuzz bytes as UTF-8 for string fields
    let fuzz_str = String::from_utf8_lossy(fuzz_content);

    // Mutate the selected field — must not panic
    let result = match field_selector {
        0 => state.update_entry(uuid, &fuzz_str, "", b"pw", "", ""),
        1 => state.update_entry(uuid, "t", &fuzz_str, b"pw", "", ""),
        2 => state.update_entry(uuid, "t", "u", fuzz_content, "", ""),
        3 => state.update_entry(uuid, "t", "u", b"pw", &fuzz_str, ""),
        _ => state.update_entry(uuid, "t", "u", b"pw", "", &fuzz_str),
    };

    if result.is_err() {
        return;
    }

    // Save to temp file — must not panic
    let tmp = tempfile::NamedTempFile::new().expect("tempfile");
    let tmp_path = tmp.path().to_str().expect("path");
    if state.save_to(tmp_path).is_err() {
        return;
    }

    // Reopen — must not panic or crash
    let _ = citadel_core::vault::VaultState::open(tmp_path, FIXTURE_PASSWORD);
});
