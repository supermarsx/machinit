#!/bin/bash
# Validate that the script can run FSE actions synchronously when --fse-sync is passed
set -euo pipefail

SCRIPT=scripts/052_configure_finder_and_sidebar.sh

echo "Testing Finder FSE synchronous mode (dry-run)..."

# No flag needed anymore — synchronous mode is the default. Test both default and explicit.
OUT_DEFAULT=$(DRY_RUN=true "$SCRIPT" --add-sidebar-only 2>&1 || true)
OUT_FLAG=$(DRY_RUN=true "$SCRIPT" --add-sidebar-only --fse-sync 2>&1 || true)

if echo "$OUT_DEFAULT" | grep -q "Running FSE command synchronously" &&
    echo "$OUT_DEFAULT" | grep -q "FSE sync mode — reusing Finder window" &&
    echo "$OUT_DEFAULT" | grep -q "Adding 'Recents' to Finder sidebar" &&
    echo "$OUT_DEFAULT" | grep -q "Sleeping 2.5s" &&
    echo "$OUT_FLAG" | grep -q "Running FSE command synchronously" &&
    echo "$OUT_FLAG" | grep -q "Sleeping 2.5s"; then
    echo "PASS: FSE synchronous mode outputs expected diagnostic lines"
    exit 0
else
    echo "FAIL: FSE synchronous mode output mismatch:" >&2
    echo "$OUT" >&2
    exit 1
fi
