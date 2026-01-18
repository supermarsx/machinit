#!/bin/bash
# Verify verbose debug logs are emitted to stderr when MACHINIT_FSE_VERBOSE=1
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
    # behave normally and remove matching lines
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
export MACHINIT_FSE_VERBOSE=1

# Ensure targets exist
mkdir -p "$TMPDIR/target1"
mkdir -p "$TMPDIR/target2"

# Add an entry
ERR=$(python3 scripts/lib/finder_sidebar_editor.py add "$TMPDIR/target1" --name Projects 2>&1 >/dev/null || true)
if echo "$ERR" | grep -q "FSE DEBUG"; then
    echo "PASS: debug info printed for add"
else
    echo "FAIL: expected debug output for add" >&2
    echo "$ERR" >&2
    rm -rf "$TMPDIR"
    exit 1
fi

# Remove entry
ERR2=$(python3 scripts/lib/finder_sidebar_editor.py remove Projects 2>&1 >/dev/null || true)
if echo "$ERR2" | grep -q "FSE DEBUG"; then
    echo "PASS: debug info printed for remove"
else
    echo "FAIL: expected debug output for remove" >&2
    echo "$ERR2" >&2
    rm -rf "$TMPDIR"
    exit 1
fi

rm -rf "$TMPDIR"
exit 0
