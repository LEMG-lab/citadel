#!/bin/bash
set -euo pipefail

# Build Smaug.app with hardened runtime.
# Usage: ./scripts/build-app.sh
# Output: ./Smaug.app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$ROOT/Smaug.app"

echo "==> Building Rust core..."
cd "$ROOT"
cargo build --release --target aarch64-apple-darwin

echo "==> Building Swift app..."
cd "$ROOT/CitadelApp"
swift build -c release

echo "==> Creating Smaug.app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Copy binary (Swift target is still named "Citadel"; rename to "Smaug" for the bundle)
cp "$ROOT/CitadelApp/.build/arm64-apple-macosx/release/Citadel" "$APP/Contents/MacOS/Smaug"

# Copy Info.plist
cp "$ROOT/CitadelApp/Info.plist" "$APP/Contents/"

echo "==> Signing with hardened runtime (Developer ID)..."
codesign --force --deep --options runtime \
    --sign "Apple Development: luis@expertop.com (AKT66WTDPP)" \
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
echo "Note: The Swift executable target is still named 'Citadel' but the binary is"
echo "      copied as 'Smaug' inside the .app bundle."
