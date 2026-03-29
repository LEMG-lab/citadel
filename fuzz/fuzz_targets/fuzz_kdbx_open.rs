#![no_main]

use libfuzzer_sys::fuzz_target;
use std::io::Write;

fuzz_target!(|data: &[u8]| {
    // Write fuzz data to a temp file (VaultState::open reads from a path)
    let tmp = tempfile::NamedTempFile::new().expect("tempfile");
    let path = tmp.path().to_str().expect("path");
    std::fs::write(path, data).expect("write");

    // Attempt to open with a fixed test password — must not panic
    let _ = citadel_core::vault::VaultState::open(path, b"Test123");

    // Attempt with empty password — must not panic
    let _ = citadel_core::vault::VaultState::open(path, b"");

    // Attempt with a long password — must not panic
    let _ = citadel_core::vault::VaultState::open(path, &[0x41; 4096]);
});
