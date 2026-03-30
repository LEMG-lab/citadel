#!/bin/bash
set -euo pipefail

# Reproducible build for Smaug.app.
#
# Records toolchain versions, builds with locked dependencies,
# creates the .app bundle, computes checksums, and writes
# build-manifest.json.
#
# Usage: ./scripts/reproducible-build.sh
# Output: ./Smaug.app + ./build-manifest.json

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$ROOT/Smaug.app"
MANIFEST="$ROOT/build-manifest.json"

# ---------------------------------------------------------------
# 1. Record environment
# ---------------------------------------------------------------
echo "==> Recording build environment..."
RUSTC_VERSION=$(rustc --version)
SWIFT_VERSION=$(swift --version 2>&1 | head -1)
GIT_COMMIT=$(git -C "$ROOT" rev-parse HEAD)
GIT_DIRTY=$(git -C "$ROOT" diff --quiet && echo "false" || echo "true")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_BUILD=$(sw_vers -buildVersion)
ARCH=$(uname -m)

echo "  rustc:   $RUSTC_VERSION"
echo "  swift:   $SWIFT_VERSION"
echo "  commit:  $GIT_COMMIT (dirty: $GIT_DIRTY)"
echo "  date:    $BUILD_DATE"
echo "  macOS:   $MACOS_VERSION ($MACOS_BUILD)"
echo "  arch:    $ARCH"

# ---------------------------------------------------------------
# 2. Build Rust core with locked dependencies
# ---------------------------------------------------------------
echo ""
echo "==> Building Rust core (release, locked)..."
cd "$ROOT"
cargo build --release --locked --target aarch64-apple-darwin

# ---------------------------------------------------------------
# 3. Copy generated C header
# ---------------------------------------------------------------
echo "==> Copying C header..."
cp "$ROOT/citadel_core.h" "$ROOT/CitadelApp/CCitadelCore/citadel_core.h"

# ---------------------------------------------------------------
# 4. Build Swift app
# ---------------------------------------------------------------
echo "==> Building Swift app (release)..."
cd "$ROOT/CitadelApp"
swift build -c release

# ---------------------------------------------------------------
# 5. Create .app bundle
# ---------------------------------------------------------------
echo "==> Creating Smaug.app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Copy binary (Swift target is still named "Citadel"; rename to "Smaug" for the bundle)
cp "$ROOT/CitadelApp/.build/release/Citadel" "$APP/Contents/MacOS/Smaug"
cp "$ROOT/CitadelApp/Info.plist" "$APP/Contents/"

# ---------------------------------------------------------------
# 6. Sign with hardened runtime
# ---------------------------------------------------------------
echo "==> Signing with hardened runtime (ad-hoc)..."
codesign --force --options runtime \
    --entitlements "$ROOT/Citadel.entitlements" \
    --sign - \
    "$APP"

# ---------------------------------------------------------------
# 7. Compute checksums
# ---------------------------------------------------------------
echo "==> Computing checksums..."
BINARY_SHA256=$(shasum -a 256 "$APP/Contents/MacOS/Smaug" | awk '{print $1}')
APP_SHA256=$(find "$APP" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')
RUST_LIB_SHA256=$(shasum -a 256 "$ROOT/target/aarch64-apple-darwin/release/libcitadel_core.a" | awk '{print $1}')

echo "  binary:   $BINARY_SHA256"
echo "  app:      $APP_SHA256"
echo "  rust lib: $RUST_LIB_SHA256"

# ---------------------------------------------------------------
# 8. Write build manifest
# ---------------------------------------------------------------
echo "==> Writing build-manifest.json..."
cat > "$MANIFEST" <<MANIFEST_EOF
{
  "build_date": "$BUILD_DATE",
  "git_commit": "$GIT_COMMIT",
  "git_dirty": $GIT_DIRTY,
  "architecture": "$ARCH",
  "macos_version": "$MACOS_VERSION",
  "macos_build": "$MACOS_BUILD",
  "rustc_version": "$RUSTC_VERSION",
  "swift_version": "$SWIFT_VERSION",
  "cargo_locked": true,
  "checksums": {
    "binary_sha256": "$BINARY_SHA256",
    "app_bundle_sha256": "$APP_SHA256",
    "rust_lib_sha256": "$RUST_LIB_SHA256"
  }
}
MANIFEST_EOF

echo ""
echo "Done: $APP"
echo "Manifest: $MANIFEST"
echo ""
echo "To verify a build:"
echo "  shasum -a 256 Smaug.app/Contents/MacOS/Smaug"
echo "  Expected: $BINARY_SHA256"
