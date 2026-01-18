#!/bin/bash
# Simulate mysides that reports success on remove but doesn't actually remove anything.
set -euo pipefail

TMPDIR=$(mktemp -d /tmp/machinit_test_mysides.XXXXXX)
STATE_FILE="$TMPDIR/state.txt"
FAKE_MYSIDES="$TMPDIR/mysides"

cat >"$FAKE_MYSIDES" <<'EOF'
#!/bin/bash
# Fake mysides that returns success for remove but doesn't modify state
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
    # intentionally report success but DO NOT modify the state file
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

# add entry
python3 scripts/lib/finder_sidebar_editor.py add "$TMPDIR/target1" --name Projects

# try to remove — should fail because mysides does nothing (though returns 0)
if python3 scripts/lib/finder_sidebar_editor.py remove Projects; then
    echo "FAIL: remove should have failed because mysides no-op" >&2
    rm -rf "$TMPDIR"
    exit 1
else
    echo "PASS: remove failed as expected when mysides returned success but did not remove"
fi

rm -rf "$TMPDIR"
exit 0
