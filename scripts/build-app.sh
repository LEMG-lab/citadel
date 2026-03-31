#!/bin/bash
set -euo pipefail

# Build Smaug.app with hardened runtime.
# Usage: ./scripts/build-app.sh
# Output: ./Smaug.app
#
# Order matters: ALL resources must be inside the bundle BEFORE codesign.
# Signing after resource changes invalidates the code signature.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="$ROOT/Smaug.app"

# ── 1. Build Rust core ──────────────────────────────────────────────
echo "==> Building Rust core..."
cd "$ROOT"
cargo build --release --target aarch64-apple-darwin

# ── 2. Build Swift app ──────────────────────────────────────────────
echo "==> Building Swift app..."
cd "$ROOT/CitadelApp"
swift build -c release

# ── 3. Create .app bundle structure ─────────────────────────────────
echo "==> Creating Smaug.app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# ── 4. Copy binary ──────────────────────────────────────────────────
cp "$ROOT/CitadelApp/.build/arm64-apple-macosx/release/Citadel" "$APP/Contents/MacOS/Smaug"

# ── 5. Copy Info.plist ──────────────────────────────────────────────
cp "$ROOT/CitadelApp/Info.plist" "$APP/Contents/"

# ── 6. Embed provisioning profile ──────────────────────────────────
cp "$ROOT/embedded.provisionprofile" "$APP/Contents/embedded.provisionprofile"

# ── 7. Copy smaug-dragon.png to Resources ──────────────────────────
cp "$ROOT/CitadelApp/App/Resources/smaug-dragon.png" "$APP/Contents/Resources/smaug-dragon.png"

# ── 8. Copy .icns icon to Resources ────────────────────────────────
cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# ── 9. Sign inner binary with hardened runtime ──────────────────────
echo "==> Signing executable with hardened runtime..."
codesign --force --options runtime \
    --entitlements "$ROOT/Citadel.entitlements" \
    --sign "Apple Development: luis@expertop.com (AKT66WTDPP)" \
    "$APP/Contents/MacOS/Smaug"

# ── 10. Sign outer bundle ──────────────────────────────────────────
echo "==> Signing app bundle..."
codesign --force --options runtime \
    --entitlements "$ROOT/Citadel.entitlements" \
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
