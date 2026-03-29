#!/bin/bash
# Quick smoke test: run each fuzz target for 60 seconds.
# Requires: cargo install cargo-fuzz
# Usage: ./fuzz/run_fuzz.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

if ! command -v cargo-fuzz &>/dev/null && ! cargo fuzz --help &>/dev/null 2>&1; then
    echo "cargo-fuzz not found. Install with: cargo install cargo-fuzz"
    exit 1
fi

echo "=== Fuzz target: fuzz_kdbx_open (60s) ==="
cargo fuzz run fuzz_kdbx_open -- -max_total_time=60 -max_len=65536

echo ""
echo "=== Fuzz target: fuzz_kdbx_roundtrip (60s) ==="
cargo fuzz run fuzz_kdbx_roundtrip -- -max_total_time=60 -max_len=4096

echo ""
echo "=== All fuzz targets completed without crashes ==="
