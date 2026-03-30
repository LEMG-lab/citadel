#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Citadel"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="/Applications"
INSTALL_PATH="${INSTALL_DIR}/${APP_BUNDLE}"

echo "=== Building ${APP_NAME} ==="

# 1. Clean and build fresh release binary
swift package clean
swift build -c release
echo "Build OK"

BINARY=".build/arm64-apple-macosx/release/${APP_NAME}"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at ${BINARY}"
    exit 1
fi

# 2. Remove old .app completely
if [ -d "$INSTALL_PATH" ]; then
    echo "Removing old ${INSTALL_PATH}"
    rm -rf "$INSTALL_PATH"
fi

# 3. Create fresh .app bundle structure
echo "Creating app bundle"
mkdir -p "${INSTALL_PATH}/Contents/MacOS"
mkdir -p "${INSTALL_PATH}/Contents/Resources"

# 4. Info.plist
cat > "${INSTALL_PATH}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Citadel</string>
    <key>CFBundleIdentifier</key>
    <string>com.citadel.app</string>
    <key>CFBundleName</key>
    <string>Citadel</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.5</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# 5. Copy binary
cp "$BINARY" "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}"

# 6. Sign with --deep
echo "Signing with codesign --deep"
codesign --force --deep --options runtime --sign - "$INSTALL_PATH"

# 7. Verify signature
echo "Verifying signature"
if codesign --verify --deep --strict "$INSTALL_PATH" 2>&1; then
    echo "=== Signature OK ==="
    echo "Installed to ${INSTALL_PATH}"
else
    echo "ERROR: Signature verification failed!"
    rm -rf "$INSTALL_PATH"
    exit 1
fi
