#!/bin/bash
# ============================================================================
# Installs Citadel health check as a daily launchd job
# Runs automatically at 10:00 AM every day
# Shows a macOS notification ONLY if something is wrong
# ============================================================================

SCRIPT_DIR="$HOME/Projects/citadel/scripts"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$PLIST_DIR/com.lemg-lab.citadel.healthcheck.plist"

mkdir -p "$SCRIPT_DIR"
mkdir -p "$PLIST_DIR"

# Copy healthcheck script
cp "$(dirname "$0")/healthcheck.sh" "$SCRIPT_DIR/healthcheck.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/healthcheck.sh"

# Create launchd plist
cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lemg-lab.citadel.healthcheck</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SCRIPT_DIR}/healthcheck.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>10</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/.citadel/.healthcheck/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.citadel/.healthcheck/launchd-stderr.log</string>
</dict>
</plist>
EOF

# Load the agent
launchctl unload "$PLIST_FILE" 2>/dev/null
launchctl load "$PLIST_FILE"

echo "Citadel health check installed."
echo ""
echo "  Runs daily at 10:00 AM"
echo "  Notifies ONLY if problems are found"
echo "  Logs: ~/.citadel/.healthcheck/"
echo ""
echo "  Manual run: bash $SCRIPT_DIR/healthcheck.sh"
echo "  Uninstall:  launchctl unload $PLIST_FILE && rm $PLIST_FILE"
echo ""

# Run it now as a first check
echo "Running first check now..."
echo ""
bash "$SCRIPT_DIR/healthcheck.sh"
