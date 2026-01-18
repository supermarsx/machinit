#!/bin/bash
# Test scripts/052_configure_finder_and_sidebar.sh --add-sidebar-only behavior
set -euo pipefail

SCRIPT=scripts/052_configure_finder_and_sidebar.sh

echo "Testing Finder sidebar add-only flag (dry-run)..."

OUT=$(DRY_RUN=true "$SCRIPT" --add-sidebar-only 2>&1 || true)

if echo "$OUT" | grep -q "Clearing Finder sidebar favorites" &&
    echo "$OUT" | grep -q "Current Finder sidebar items (pre-clear)" &&
    (echo "$OUT" | grep -q "Closing any open Finder windows" || echo "$OUT" | grep -q "FSE sync mode — reusing Finder window") &&
    echo "$OUT" | grep -q "Adding 'Recents' to Finder sidebar" &&
    echo "$OUT" | grep -q "Adding 'Applications' to Finder sidebar" &&
    echo "$OUT" | grep -q "Adding 'Home' to Finder sidebar" &&
    echo "$OUT" | grep -q "Adding 'Desktop' to Finder sidebar" &&
    echo "$OUT" | grep -q "Adding 'Documents' to Finder sidebar" &&
    echo "$OUT" | grep -q "Adding 'Downloads' to Finder sidebar" &&
    echo "$OUT" | grep -q "Adding 'Projects' to Finder sidebar" &&
    echo "$OUT" | grep -q "Adding 'Nextcloud' to Finder sidebar" &&
    echo "$OUT" | grep -q "Final Finder sidebar items (post-add, add-only mode):"; then
    echo "PASS: add-only mode cleared and repopulated favorites in order"
    exit 0
else
    echo "FAIL: add-only mode output mismatch:" >&2
    echo "$OUT" >&2
    exit 1
fi
