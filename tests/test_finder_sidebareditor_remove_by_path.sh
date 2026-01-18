#!/bin/bash
# Test finder_sidebar_editor remove-by-path using fake mysides
set -euo pipefail

TMPDIR=$(mktemp -d /tmp/machinit_test_mysides.XXXXXX)
STATE_FILE="$TMPDIR/state.txt"
FAKE_MYSIDES="$TMPDIR/mysides"

cat >"$FAKE_MYSIDES" <<'EOF'
#!/bin/bash
# Minimal fake mysides script for tests
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
    exit 2
    ;;
esac
EOF

chmod +x "$FAKE_MYSIDES"

export MACHINIT_MYSIDES="$FAKE_MYSIDES"
export MACHINIT_USE_MYSIDES=1
export MYSIDES_STATE="$STATE_FILE"

# Ensure targets exist
mkdir -p "$TMPDIR/target1"
mkdir -p "$TMPDIR/target2"

# Pre-populate state via add
python3 scripts/lib/finder_sidebar_editor.py add "$TMPDIR/target1" --name Projects
python3 scripts/lib/finder_sidebar_editor.py add "$TMPDIR/target2" --name Documents

# Remove by path
python3 scripts/lib/finder_sidebar_editor.py remove-by-path "$TMPDIR/target1"

OUT=$(python3 scripts/lib/finder_sidebar_editor.py list)

if echo "$OUT" | grep -q "Documents" && ! echo "$OUT" | grep -q "Projects"; then
    echo "PASS: remove-by-path removed the target path entry"
    rm -rf "$TMPDIR"
    exit 0
else
    echo "FAIL: remove-by-path did not remove expected entry" >&2
    echo "$OUT" >&2
    rm -rf "$TMPDIR"
    exit 1
fi
