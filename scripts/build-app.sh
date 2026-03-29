#!/bin/bash
set -euo pipefail

# Build Citadel.app with hardened runtime.
# Usage: ./scripts/build-app.sh
# Output: ./Citadel.app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$ROOT/Citadel.app"

echo "==> Building Rust core..."
cd "$ROOT"
cargo build --release --target aarch64-apple-darwin

echo "==> Building Swift app..."
cd "$ROOT/CitadelApp"
swift build -c release

echo "==> Creating Citadel.app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Copy binary
cp "$ROOT/CitadelApp/.build/release/Citadel" "$APP/Contents/MacOS/"

# Copy Info.plist
cp "$ROOT/CitadelApp/Info.plist" "$APP/Contents/"

echo "==> Signing with hardened runtime (ad-hoc)..."
codesign --force --options runtime \
    --entitlements "$ROOT/Citadel.entitlements" \
    --sign - \
    "$APP"

echo ""
echo "Done: $APP"
echo ""
echo "Hardened runtime protections active:"
echo "  - Debugger attachment blocked"
echo "  - Dylib injection blocked"
echo "  - DYLD environment variables blocked"
echo "  - Core dumps disabled (RLIMIT_CORE = 0)"
echo ""
echo "Verify: codesign -dvv '$APP'"
