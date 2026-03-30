#!/bin/bash
# ============================================================================
# SMAUG HEALTH CHECK — runs daily, alerts only on problems
# ============================================================================
# Install: bash ~/Projects/citadel/scripts/install-healthcheck.sh
# Manual:  bash ~/Projects/citadel/scripts/healthcheck.sh
# ============================================================================

VAULT_DIR="$HOME/.smaug"
VAULT_FILE="$VAULT_DIR/vault.kdbx"
LOG_DIR="$VAULT_DIR/.healthcheck"
TODAY=$(date +%Y-%m-%d)
LOG="$LOG_DIR/$TODAY.log"
ALERT_FILE="$LOG_DIR/ALERT"
ENTRY_COUNT_FILE="$LOG_DIR/entry-count"

mkdir -p "$LOG_DIR"

PROBLEMS=0
WARNINGS=0

log() { echo "$(date +%H:%M:%S) $1" >> "$LOG"; }
problem() { PROBLEMS=$((PROBLEMS+1)); log "PROBLEM: $1"; }
warning() { WARNINGS=$((WARNINGS+1)); log "WARNING: $1"; }
ok() { log "OK: $1"; }

log "=== Smaug health check ==="

# 1. Vault file exists
if [ ! -f "$VAULT_FILE" ]; then
    problem "vault.kdbx NOT FOUND at $VAULT_FILE"
else
    ok "vault.kdbx exists"

    # 2. Magic bytes
    MAGIC=$(xxd -l 8 -p "$VAULT_FILE" 2>/dev/null)
    if [ "$MAGIC" != "03d9a29a67fb4bb5" ]; then
        problem "vault.kdbx has WRONG magic bytes: $MAGIC (file may be corrupt)"
    else
        ok "KDBX magic bytes correct"
    fi

    # 3. File size sanity (not empty, not suspiciously small)
    FSIZE=$(stat -f '%z' "$VAULT_FILE" 2>/dev/null || stat -c '%s' "$VAULT_FILE" 2>/dev/null)
    if [ "$FSIZE" -lt 500 ]; then
        problem "vault.kdbx is only $FSIZE bytes (suspiciously small, may be corrupt)"
    else
        ok "vault.kdbx size: $FSIZE bytes"
    fi

    # 4. File size didn't shrink drastically since last check
    PREV_SIZE_FILE="$LOG_DIR/prev-size"
    if [ -f "$PREV_SIZE_FILE" ]; then
        PREV_SIZE=$(cat "$PREV_SIZE_FILE")
        if [ "$FSIZE" -lt $((PREV_SIZE / 2)) ] && [ "$PREV_SIZE" -gt 1000 ]; then
            problem "vault.kdbx shrank from $PREV_SIZE to $FSIZE bytes (possible data loss)"
        fi
    fi
    echo "$FSIZE" > "$PREV_SIZE_FILE"

    # 5. Permissions
    PERMS=$(stat -f '%Lp' "$VAULT_FILE" 2>/dev/null || stat -c '%a' "$VAULT_FILE" 2>/dev/null)
    if [ "$PERMS" != "644" ] && [ "$PERMS" != "600" ]; then
        warning "vault.kdbx permissions: $PERMS (expected 600 or 644)"
    else
        ok "permissions: $PERMS"
    fi

    # 6. No plaintext leaks
    SUSPECT=$(strings "$VAULT_FILE" 2>/dev/null | grep -iE "password|secret|bank|gmail" | head -1)
    if [ -n "$SUSPECT" ]; then
        problem "Suspicious plaintext found in vault.kdbx: '$SUSPECT'"
    else
        ok "no plaintext detected in vault binary"
    fi
fi

# 7. No leftover .tmp files
TMP_COUNT=$(find "$VAULT_DIR" -name "*.tmp" 2>/dev/null | wc -l | tr -d ' ')
if [ "$TMP_COUNT" -gt 0 ]; then
    problem "$TMP_COUNT .tmp file(s) found (interrupted save detected)"
else
    ok "no leftover .tmp files"
fi

# 8. Snapshot count (max 3 .prev files)
PREV_COUNT=$(find "$VAULT_DIR" -name "*.prev*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$PREV_COUNT" -gt 3 ]; then
    warning "$PREV_COUNT .prev files (expected max 3)"
else
    ok "snapshot count: $PREV_COUNT"
fi

# 9. Old backup files (should not accumulate)
OLD_BACKUPS=$(find "$VAULT_DIR" -name "vault-backup-*.kdbx" -mtime +7 2>/dev/null | wc -l | tr -d ' ')
if [ "$OLD_BACKUPS" -gt 0 ]; then
    warning "$OLD_BACKUPS backup file(s) older than 7 days still present"
fi

# 10. Spotlight still blocked
if [ ! -f "$VAULT_DIR/.metadata_never_index" ]; then
    problem ".metadata_never_index missing (Spotlight may index vault)"
fi

# 11. Not in iCloud
BIRD_XATTR=$(xattr -p com.apple.bird.metadata "$HOME/Documents" 2>/dev/null || true)
if [ -n "$BIRD_XATTR" ] && [[ "$VAULT_DIR" == "$HOME/Documents/"* ]]; then
    problem "vault is inside iCloud-synced Documents folder"
else
    ok "vault is outside iCloud sync"
fi

# 12. Time Machine exclusion
TM_CHECK=$(tmutil isexcluded "$VAULT_DIR" 2>/dev/null || echo "unknown")
if echo "$TM_CHECK" | grep -q "Excluded"; then
    ok "excluded from Time Machine"
else
    warning "vault directory NOT excluded from Time Machine"
fi

# 13. FileVault
FV=$(fdesetup status 2>/dev/null || echo "unknown")
if echo "$FV" | grep -q "On"; then
    ok "FileVault is ON"
else
    warning "FileVault is OFF (disk not encrypted at rest)"
fi

# 14. Check last modification time (vault should be touched if user is active)
LAST_MOD=$(stat -f '%m' "$VAULT_FILE" 2>/dev/null || stat -c '%Y' "$VAULT_FILE" 2>/dev/null)
NOW=$(date +%s)
DAYS_SINCE=$(( (NOW - LAST_MOD) / 86400 ))
if [ "$DAYS_SINCE" -gt 30 ]; then
    warning "vault not modified in $DAYS_SINCE days (is Smaug being used?)"
fi

# Result
log "=== Result: $PROBLEMS problems, $WARNINGS warnings ==="

if [ "$PROBLEMS" -gt 0 ]; then
    echo "SMAUG HEALTH CHECK: $PROBLEMS PROBLEM(S) DETECTED" > "$ALERT_FILE"
    echo "Check log: $LOG" >> "$ALERT_FILE"
    grep "PROBLEM:" "$LOG" >> "$ALERT_FILE"

    # Show macOS notification
    osascript -e "display notification \"$PROBLEMS problem(s) found. Check $LOG\" with title \"Smaug Health Check\" subtitle \"Action required\"" 2>/dev/null || true

    # Also print to stdout if run manually
    echo ""
    echo "SMAUG: $PROBLEMS PROBLEM(S) DETECTED"
    grep "PROBLEM:" "$LOG" | sed 's/^.*PROBLEM: /  /'
    echo ""
    echo "Log: $LOG"
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    rm -f "$ALERT_FILE"
    echo ""
    echo "SMAUG: OK ($WARNINGS minor warning(s))"
    grep "WARNING:" "$LOG" | sed 's/^.*WARNING: /  /'
    exit 0
else
    rm -f "$ALERT_FILE"
    echo "SMAUG: ALL CLEAR"
    exit 0
fi
