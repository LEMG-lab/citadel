# Smaug

A personal password vault for macOS with a Rust crypto core and native SwiftUI interface. KDBX 4.x format. Local only. No cloud. No account. No subscription.

## Features

- **KDBX 4.x format** — open your vault with KeePassXC or Strongbox at any time
- **Argon2id + ChaCha20** — 256 MB memory-hard KDF, modern stream cipher
- **Atomic save pipeline** — write → fsync → validate → snapshot → rename; no data loss on crash
- **Auto-lock** — configurable idle timeout locks the vault and zeroes sensitive memory
- **Clipboard protection** — auto-clear after configurable interval, macOS ConcealedType
- **Password generator** — configurable length and character sets
- **Snapshot history** — keeps 3 previous versions of the vault file
- **Crash recovery** — automatic recovery from `.prev` or `.tmp` if the vault file is missing

## Architecture

```
┌─────────────────────────────┐
│  SwiftUI App (macOS 15+)    │  CitadelApp/App/
│  AppState · Views · UX      │
├─────────────────────────────┤
│  Swift Library (CitadelCore)│  CitadelApp/Sources/
│  VaultEngine · Persistence  │
│  SecureClipboard · AutoLock │
├─────────────────────────────┤
│  C FFI boundary             │  citadel_core.h (cbindgen)
├─────────────────────────────┤
│  Rust Core                  │  src/
│  keepass-rs · Argon2id      │
│  ChaCha20 · HMAC-SHA-256    │
└─────────────────────────────┘
```

- **Rust core** (`src/`) — KDBX parsing, encryption, entry CRUD, password generation. Built on [keepass-rs](https://github.com/sseemayer/keepass-rs). Compiled as a static library with a C FFI.
- **Swift wrapper** (`CitadelApp/Sources/`) — type-safe Swift API over the FFI, atomic save pipeline with `F_FULLFSYNC`, secure clipboard, auto-lock timer.
- **SwiftUI app** (`CitadelApp/App/`) — native macOS interface. Lock screen, entry list, detail view, password generator, settings.

### Cryptographic choices

| Component | Algorithm |
|-----------|-----------|
| KDF | Argon2id v1.3 (256 MB, 3 iterations, 4 parallelism) |
| Outer cipher | ChaCha20 |
| Inner cipher | ChaCha20 |
| Integrity | HMAC-SHA-256 (KDBX block stream) |
| RNG | `SecRandomCopyBytes` (vault ops), `rand::rng()` ChaCha20-CSPRNG (password gen) |

## Build

### Prerequisites

- macOS 15+
- Xcode 16+ (Swift 6)
- Rust 1.75+ (`rustup`)

### Build the Rust core

```bash
cargo build --release --target aarch64-apple-darwin
```

### Build and run the app (development)

```bash
cd CitadelApp
swift build
swift run Citadel
```

Or open `CitadelApp/Package.swift` in Xcode and run the `Citadel` scheme.

### Build Smaug.app with hardened runtime (recommended)

```bash
./scripts/build-app.sh
```

This builds Rust + Swift in release mode, creates `Smaug.app`, and signs it with hardened runtime (ad-hoc). Hardened runtime blocks debugger attachment, dylib injection, and DYLD environment variables. Open with `open Smaug.app` or drag to `/Applications`.

### Reproducible build with manifest

```bash
./scripts/reproducible-build.sh
```

This builds with `cargo build --release --locked` (exact dependency versions from Cargo.lock), creates `Smaug.app`, signs it with hardened runtime, and writes `build-manifest.json` containing toolchain versions, git commit, and SHA-256 checksums. To verify a build:

```bash
cat build-manifest.json                              # check recorded checksums
shasum -a 256 Smaug.app/Contents/MacOS/Smaug         # compare binary hash
```

### Run tests

```bash
# Rust tests (unit + integration + interop + negative corpus)
cargo test

# Swift tests (engine + persistence + stress + memory)
cd CitadelApp && swift test
```

### Run fuzz tests (requires cargo-fuzz)

```bash
cargo install cargo-fuzz
./fuzz/run_fuzz.sh
```

## Security model

See [SECURITY.md](SECURITY.md) for the full threat model, accepted limitations, and cryptographic details.

## Escape hatch

If Smaug ever stops working, open `vault.kdbx` with [KeePassXC](https://keepassxc.org/) (free, open source, cross-platform) or [Strongbox](https://strongboxsafe.com/) using your master password. No additional software or keys are needed.

## Development

This project was built in a single development session with AI-assisted development (Claude), then audited across 5 rounds by 6 independent AI models. All identified security issues were resolved and verified with 70 automated tests (41 Rust + 29 Swift) covering unit, integration, interop, negative corpus, stress/fuzz, memory cleanup, and mlock/core-dump scenarios.

## License

[MIT](LICENSE) — Copyright 2026 Luis Maumejean
