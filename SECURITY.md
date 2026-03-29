# Citadel Security Model

## What Citadel protects against
- Offline brute force of stolen vault file (Argon2id 256MB, ChaCha20)
- Data loss from interrupted saves (atomic save pipeline with snapshots)
- Accidental plaintext exposure (clipboard auto-clear, concealed type, auto-lock, press-and-hold reveal)
- App lock-in (KDBX format, openable by KeePassXC and Strongbox)
- Silent data corruption (post-write validation with entry count verification, HMAC verification)
- Spotlight indexing of vault directory (.metadata_never_index)
- Screen capture of vault windows (sharingType = .none on all windows including sheets)
- Inactivity auto-lock (configurable timeout, plus immediate lock on sleep, screensaver, and fast user switch)
- Sensitive memory paging to swap (mlock on master password buffer in Rust core)
- Core dumps containing secrets (RLIMIT_CORE = 0 set on first FFI call)
- Debugger attachment and dylib injection (hardened runtime when built as .app bundle)
- Filesystem isolation (App Sandbox — vault accessible only within app container; no network entitlements)
- Two-factor vault protection (optional keyfile in addition to master password)
- Vault file permissions (chmod 600 on vault, chmod 700 on vault directory after every save)
- Symlink-safe saves (vault path resolved before writing .tmp to prevent cross-device rename failures)
- Audit trail (file-based audit log with 30-day rotation; logs unlock, lock, entry changes, password changes)

## What Citadel does NOT protect against
- A fully compromised endpoint (keylogger, screen recorder, memory dump while unlocked)
- Clipboard managers that ignore the ConcealedType convention
- Physical access to an unlocked Mac with the vault open
- Weak master passwords (the vault's security is bounded by password entropy; a strength meter is shown during entry editing and password generation)
- macOS swap/hibernation writing sensitive memory to disk (mitigated by mlock on password buffer + Rust zeroize; Database struct internals may still be paged)
- Screen recording by apps with Accessibility permissions
- Time Machine backing up .prev snapshot files and vault-backup-*.kdbx files (see below)
- Universal Clipboard syncing copied passwords to other Apple devices on the same iCloud account (ConcealedType does not prevent this; disable Handoff in System Settings if this concerns you)
- Swift/SwiftUI password strings persisting in freed heap memory after deallocation (see below)
- Clipboard not being cleared if the app is force-quit (kill -9) or crashes (the clear timer is in-process)
- Cloud sync services (iCloud, Dropbox, etc.) uploading the vault if stored in a synced folder (a warning is shown on launch, but the user must move the vault themselves)
- Mission Control (F3) shows vault content in window thumbnails (sharingType = .none blocks screenshots but not WindowServer compositing; requires physical access to an unlocked Mac)

## Accepted limitations

### Swift memory zeroing
SwiftUI `@State` String variables for passwords (in LockScreenView, ChangePasswordView, EntryEditView) and `VaultEntryDetail.password` as `Data` are not guaranteed to be zeroed on deallocation. Swift provides no mechanism to ensure freed heap memory is overwritten. Passwords may persist in deallocated heap and could be written to swap or hibernation files. This is a fundamental Swift/SwiftUI limitation shared by all Swift-based password managers. The Rust core uses `Zeroizing<Vec<u8>>` which provides reliable zeroing; the Swift side performs explicit `resetBytes` before releasing references, but cannot control what happens after deallocation.

### Clipboard limitations
The clipboard auto-clear timer runs in-process. If Citadel is killed (`kill -9`), crashes, or is force-quit, the clipboard is not cleared. Additionally, Universal Clipboard (Handoff) may sync copied passwords to other Apple devices on the same iCloud account for up to 2 minutes. ConcealedType marks the pasteboard item as sensitive, but this does not prevent Universal Clipboard sync. Users concerned about this should disable Handoff in System Settings > General > AirDrop & Handoff.

### Time Machine and historical vault files
Time Machine backs up `vault.kdbx` and `.prev` snapshot files. Auto-backup files created during password changes (`vault-backup-*.kdbx`) are encrypted with the old password and automatically deleted after a successful password change. If the change fails, the backup is used for rollback and then removed. Historical Time Machine snapshots may still contain older vault versions with weaker passwords. Users should exclude `~/.citadel/` from Time Machine if this concerns them (System Settings > Time Machine > Options > Exclude).

### AutoType data loss
The `sanitize_autotype` function drops AutoType configuration blocks that contain only default settings to work around a keepass-rs serialization bug (it writes `DataTransferObfuscation` as `"True"`/`"False"` but KeePassXC expects `0`/`1`). AutoType blocks with custom associations or custom sequences are preserved as-is. This means: if you have entries with default AutoType settings and edit them in Citadel, the AutoType block will be removed on save. Custom AutoType configurations (associations, custom sequences) are preserved but may cause KeePassXC to show a warning.

### Other limitations
- Master password must be valid UTF-8 (keepass-rs limitation)
- App Sandbox uses the container directory (`~/Library/Containers/com.lemg-lab.citadel/Data/.citadel/`). Users migrating from an unsandboxed install must import their vault via the lock screen. The sandbox grants `files.user-selected.read-write` for backup export and vault import, `files.bookmarks.app-scope` for security-scoped bookmarks, and `print` for recovery sheets. No network entitlements are granted.
- The keepass-rs crate (v0.10) is pre-1.0 with KDBX4 write support marked as feature-gated
- Cloud sync detection checks common paths but may not detect all sync services

## Cryptographic choices
- KDF: Argon2id v1.3 (256 MB memory, 3 iterations, 4 parallelism)
- Outer cipher: ChaCha20
- Inner cipher: ChaCha20
- Integrity: HMAC-SHA-256 (KDBX block stream)
- RNG: SecRandomCopyBytes (Apple hardware entropy) for vault operations, rand::rng() (ChaCha20-based CSPRNG) for password generation

## Escape hatch
If Citadel stops working, open vault.kdbx with KeePassXC (free, open source, cross-platform) using your master password (and keyfile, if configured). No additional software is needed.
