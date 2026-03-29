# Citadel Security Model

## What Citadel protects against
- Offline brute force of stolen vault file (Argon2id 256MB, ChaCha20)
- Data loss from interrupted saves (atomic save pipeline with snapshots)
- Accidental plaintext exposure (clipboard auto-clear, concealed type, auto-lock)
- App lock-in (KDBX format, openable by KeePassXC and Strongbox)
- Silent data corruption (post-write validation with entry count verification, HMAC verification)
- Spotlight indexing of vault directory (.metadata_never_index)
- Screen capture of vault windows (sharingType = .none on all windows including sheets)
- Vault exposure on app switch (auto-locks when app loses focus, so Cmd+Tab and app switching show the lock screen)

## What Citadel does NOT protect against
- A fully compromised endpoint (keylogger, screen recorder, memory dump while unlocked)
- Clipboard managers that ignore the ConcealedType convention
- Physical access to an unlocked Mac with the vault open
- Weak master passwords (the vault's security is bounded by password entropy)
- macOS swap/hibernation writing sensitive memory to disk (partially mitigated by Rust zeroize, not fully preventable)
- Screen recording by apps with Accessibility permissions
- Time Machine backing up .prev snapshot files and vault-backup-*.kdbx files (see below)
- Universal Clipboard syncing copied passwords to other Apple devices on the same iCloud account (ConcealedType does not prevent this; disable Handoff in System Settings if this concerns you)
- Swift/SwiftUI password strings persisting in freed heap memory after deallocation (see below)
- Clipboard not being cleared if the app is force-quit (kill -9) or crashes (the clear timer is in-process)
- Cloud sync services (iCloud, Dropbox, etc.) uploading the vault if stored in a synced folder (a warning is shown on launch, but the user must move the vault themselves)
- Mission Control (F3) may briefly show vault content in window thumbnails before auto-lock activates. This requires physical access to an unlocked Mac.

## Accepted limitations

### Swift memory zeroing
SwiftUI `@State` String variables for passwords (in LockScreenView, ChangePasswordView, EntryEditView) and `VaultEntryDetail.password` as `Data` are not guaranteed to be zeroed on deallocation. Swift provides no mechanism to ensure freed heap memory is overwritten. Passwords may persist in deallocated heap and could be written to swap or hibernation files. This is a fundamental Swift/SwiftUI limitation shared by all Swift-based password managers. The Rust core uses `Zeroizing<Vec<u8>>` which provides reliable zeroing; the Swift side performs explicit `resetBytes` before releasing references, but cannot control what happens after deallocation.

### Clipboard limitations
The clipboard auto-clear timer runs in-process. If Citadel is killed (`kill -9`), crashes, or is force-quit, the clipboard is not cleared. Additionally, Universal Clipboard (Handoff) may sync copied passwords to other Apple devices on the same iCloud account for up to 2 minutes. ConcealedType marks the pasteboard item as sensitive, but this does not prevent Universal Clipboard sync. Users concerned about this should disable Handoff in System Settings > General > AirDrop & Handoff.

### Time Machine and historical vault files
Time Machine backs up `vault.kdbx`, `.prev` snapshot files, and `vault-backup-*.kdbx` files created during password changes. Historical backups may use older, potentially weaker passwords. Backup files created during password changes (`vault-backup-*.kdbx`) use the **old** password and are not automatically cleaned up. Users should exclude `~/.citadel/` from Time Machine if this concerns them (System Settings > Time Machine > Options > Exclude).

### AutoType data loss
The `sanitize_autotype` function drops AutoType configuration blocks that contain only default settings to work around a keepass-rs serialization bug (it writes `DataTransferObfuscation` as `"True"`/`"False"` but KeePassXC expects `0`/`1`). AutoType blocks with custom associations or custom sequences are preserved as-is. This means: if you have entries with default AutoType settings and edit them in Citadel, the AutoType block will be removed on save. Custom AutoType configurations (associations, custom sequences) are preserved but may cause KeePassXC to show a warning.

### Other limitations
- Master password must be valid UTF-8 (keepass-rs limitation)
- App runs without App Sandbox (SPM executable, not .app bundle)
- The keepass-rs crate (v0.10) is pre-1.0 with KDBX4 write support marked as feature-gated
- Cloud sync detection checks common paths but may not detect all sync services

## Cryptographic choices
- KDF: Argon2id v1.3 (256 MB memory, 3 iterations, 4 parallelism)
- Outer cipher: ChaCha20
- Inner cipher: ChaCha20
- Integrity: HMAC-SHA-256 (KDBX block stream)
- RNG: SecRandomCopyBytes (Apple hardware entropy) for vault operations, rand::rng() (ChaCha20-based CSPRNG) for password generation

## Escape hatch
If Citadel stops working, open vault.kdbx with KeePassXC (free, open source, cross-platform) using your master password. No additional software or keys are needed.
