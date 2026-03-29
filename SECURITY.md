# Citadel Security Model

## What Citadel protects against
- Offline brute force of stolen vault file (Argon2id 256MB, ChaCha20)
- Data loss from interrupted saves (atomic save pipeline with snapshots)
- Accidental plaintext exposure (clipboard auto-clear, concealed type, auto-lock)
- App lock-in (KDBX format, openable by KeePassXC and Strongbox)
- Silent data corruption (post-write validation, HMAC verification)

## What Citadel does NOT protect against
- A fully compromised endpoint (keylogger, screen recorder, memory dump while unlocked)
- Clipboard managers that ignore the ConcealedType convention
- Physical access to an unlocked Mac with the vault open
- Weak master passwords (the vault's security is bounded by password entropy)
- macOS swap/hibernation writing sensitive memory to disk (partially mitigated by Rust zeroize, not fully preventable)
- Screen recording by apps with Accessibility permissions
- Time Machine backing up .prev snapshot files

## Accepted limitations
- Master password must be valid UTF-8 (keepass-rs limitation)
- AutoType blocks with only default settings are simplified on save (keepass-rs serialization workaround)
- App runs without App Sandbox (SPM executable, not .app bundle)
- Swift Data objects are not guaranteed to be zeroed after deallocation (mitigated with explicit zeroing before release)
- The keepass-rs crate (v0.10) is pre-1.0 with KDBX4 write support marked as feature-gated

## Cryptographic choices
- KDF: Argon2id v1.3 (256 MB memory, 3 iterations, 4 parallelism)
- Outer cipher: ChaCha20
- Inner cipher: ChaCha20
- Integrity: HMAC-SHA-256 (KDBX block stream)
- RNG: SecRandomCopyBytes (Apple hardware entropy) for vault operations, rand::rng() (ChaCha20-based CSPRNG) for password generation

## Escape hatch
If Citadel stops working, open vault.kdbx with KeePassXC (free, open source, cross-platform) using your master password. No additional software or keys are needed.
