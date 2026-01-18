#!/bin/bash
# Test finder_sidebar_editor add/list/remove using a fake mysides binary
set -euo pipefail

TMPDIR=$(mktemp -d /tmp/machinit_test_mysides.XXXXXX)
STATE_FILE="$TMPDIR/state.txt"
FAKE_MYSIDES="$TMPDIR/mysides"

cat >"$FAKE_MYSIDES" <<'EOF'
#!/bin/bash
# Minimal fake mysides script for tests
# STATE_FILE points to the backing file
STATE_FILE=${MYSIDES_STATE:-/tmp/machinit_mysides_state}
cmd="$1"
shift || true
case "$cmd" in
  add)
    name="$1"; shift || true
    target="$1"; shift || true
    echo "$name|$target" >> "$STATE_FILE"
    exit 0
    ;;
  list)
    if [ -f "$STATE_FILE" ]; then
      cat "$STATE_FILE"
      exit 0
    else
      exit 0
    fi
    ;;
  remove|rm)
    name="$1"; shift || true
    if [ -f "$STATE_FILE" ]; then
      grep -v "^${name}|" "$STATE_FILE" > "$STATE_FILE.tmp" || true
      mv "$STATE_FILE.tmp" "$STATE_FILE" 2>/dev/null || true
    fi
    exit 0
    ;;
  *)
    # mimic failure for unknown commands
    exit 2
    ;;
esac
EOF

chmod +x "$FAKE_MYSIDES"

# Export variables so finder_sidebar_editor picks our mysides
export MACHINIT_MYSIDES="$FAKE_MYSIDES"
# Tests should explicitly enable mysides usage
export MACHINIT_USE_MYSIDES=1
export MYSIDES_STATE="$STATE_FILE"

# Ensure targets exist
mkdir -p "$TMPDIR/target1"
mkdir -p "$TMPDIR/target2"

# Run add commands via CLI
python3 scripts/lib/finder_sidebar_editor.py add "$TMPDIR/target1" --name Projects
python3 scripts/lib/finder_sidebar_editor.py add "$TMPDIR/target2" --name Documents

# Now list and verify both entries are present
OUT=$(python3 scripts/lib/finder_sidebar_editor.py list)

if echo "$OUT" | grep -q "Projects" && echo "$OUT" | grep -q "Documents"; then
    echo "PASS: list shows added items"
else
    echo "FAIL: list output unexpected:" >&2
    echo "$OUT" >&2
    exit 1
fi

# Now try removal
python3 scripts/lib/finder_sidebar_editor.py remove Projects
OUT2=$(python3 scripts/lib/finder_sidebarditor.py list 2>/dev/null || true)

# note: older version of the script incorrectly used a different filename; allow robust check
OUT2=$(python3 scripts/lib/finder_sidebar_editor.py list)

if echo "$OUT2" | grep -q "Documents" && ! echo "$OUT2" | grep -q "Projects"; then
    echo "PASS: remove removed Projects; Documents still present"
    rm -rf "$TMPDIR"
    exit 0
else
    echo "FAIL: remove did not work as expected:" >&2
    echo "$OUT2" >&2
    rm -rf "$TMPDIR"
    exit 1
fi
