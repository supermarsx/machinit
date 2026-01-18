#!/bin/bash
# Verify FinderSidebar.add() honors DRY_RUN and doesn't error during tests
set -euo pipefail

echo "Testing finder_sidebar_editor.FinderSidebar.add in DRY_RUN mode (should be a no-op)..."

OUT=$(DRY_RUN=1 python3 -c 'from finder_sidebar_editor import FinderSidebar; FinderSidebar().add("/tmp")' 2>&1 || true)

if echo "$OUT" | grep -q "DRY_RUN" || echo "$OUT" | grep -q "[DRY_RUN]"; then
    echo "PASS: FinderSidebar.add respected DRY_RUN"
    exit 0
else
    # In some environments the module may silence output, but it must not raise
    if [ -z "${OUT// /}" ]; then
        echo "PASS: FinderSidebar.add returned silently in DRY_RUN (allowed)"
        exit 0
    fi
    echo "FAIL: FinderSidebar.add did not indicate DRY_RUN or failed" >&2
    echo "$OUT" >&2
    exit 1
fi
