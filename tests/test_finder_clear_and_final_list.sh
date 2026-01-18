#!/bin/bash
# Test the script prints a list before clearing and a final list after adding (dry-run)
set -euo pipefail

SCRIPT=scripts/052_configure_finder_and_sidebar.sh

echo "Testing Finder script prints pre-clear and post-add lists (dry-run)..."

OUT=$(DRY_RUN=true "$SCRIPT" 2>&1 || true)

if echo "$OUT" | grep -q "Current Finder sidebar items (pre-clear):" &&
    echo "$OUT" | grep -q "Final Finder sidebar items (post-add):"; then
    echo "PASS: script printed both pre-clear and post-add lists"
    exit 0
else
    echo "FAIL: missing expected pre/post list output" >&2
    echo "$OUT" >&2
    exit 1
fi
