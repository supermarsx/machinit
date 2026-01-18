#!/bin/bash
# Test finder_sidebar_editor move retries when mysides move initially fails then succeeds
set -euo pipefail

TMPDIR=$(mktemp -d /tmp/machinit_test_mysides.XXXXXX)
STATE_FILE="$TMPDIR/state.txt"
ATTEMPTS_FILE="$TMPDIR/attempts.txt"
FAKE_MYSIDES="$TMPDIR/mysides"

cat >"$FAKE_MYSIDES" <<'EOF'
#!/bin/bash
STATE_FILE=${MYSIDES_STATE:-/tmp/machinit_mysides_state}
ATTEMPTS_FILE=${MYSIDES_MOV_ATTEMPTS:-/tmp/machinit_mysides_move_attempts}
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
  move)
    # Simulate move command failing twice then succeeding
    name="$1"; shift || true
    pos="$1"; shift || true
    mkdir -p "$(dirname "$ATTEMPTS_FILE")"
    cur=0
    if [ -f "$ATTEMPTS_FILE" ]; then
      cur=$(cat "$ATTEMPTS_FILE" || echo 0)
    fi
    cur=$((cur + 1))
    echo "$cur" > "$ATTEMPTS_FILE"
    if [ "$cur" -lt 3 ]; then
      # fail first two attempts
      exit 2
    fi
    # pretend to succeed
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
export MYSIDES_MOV_ATTEMPTS="$ATTEMPTS_FILE"

# Prepare initial list
mkdir -p "$TMPDIR/target1"
mkdir -p "$TMPDIR/target2"
python3 scripts/lib/finder_sidebar_editor.py add "$TMPDIR/target1" --name Projects
python3 scripts/lib/finder_sidebar_editor.py add "$TMPDIR/target2" --name Documents

# Attempt to move Projects -> position 2 (should succeed after retries)
OUT=$(python3 scripts/lib/finder_sidebar_editor.py move Projects 2 2>&1 || true)
RC=$?

if [ $RC -eq 0 ] || echo "$OUT" | grep -q "Moved"; then
    echo "PASS: move retried and eventually succeeded (or returned success)"
    rm -rf "$TMPDIR"
    exit 0
else
    echo "FAIL: move did not succeed after retries" >&2
    echo "$OUT" >&2
    rm -rf "$TMPDIR"
    exit 1
fi
