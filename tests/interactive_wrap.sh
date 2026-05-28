#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
EXA="${EXAPLUS_BIN:-$DIR/../exaplus}"
HOST="${EXAPLUS_TEST_HOST:-localhost}"
PORT="${EXAPLUS_TEST_PORT:-8563}"
CONN="$HOST/nocertcheck:$PORT"
SESSION="exaplus_wrap_test_$$"
KH="/tmp/exaplus_known_hosts_wrap_$$"
HIST="/tmp/exaplus_history_wrap_$$"
COLS=72
ROWS=20
QUERY="SELECT TABLE_NAME FROM EXA_ALL_TABLES WHERE TABLE_SCHEMA = 'TPC' AND TABLE_NAME IN ('LINEITEM', 'ORDERS') ORDER BY TABLE_NAME"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -f "$KH" "$HIST"
}
trap cleanup EXIT

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP interactive_wrap.sh (tmux not installed)"
  exit 0
fi

wait_for_pane() {
  local regex="$1" timeout="${2:-60}" waited=0 pane
  while true; do
    pane="$(tmux capture-pane -J -p -t "$SESSION:0.0")"
    if printf '%s\n' "$pane" | grep -Eq "$regex"; then
      return 0
    fi
    sleep 0.2
    waited=$((waited + 1))
    if (( waited >= timeout * 5 )); then
      echo "Timed out waiting for /$regex/" >&2
      printf '%s\n' "$pane" >&2
      return 1
    fi
  done
}

tmux new-session -d -x "$COLS" -y "$ROWS" -s "$SESSION" \
  "env COLUMNS=$COLS LINES=$ROWS EXAPLUS_KNOWN_HOSTS='$KH' EXAPLUS_HISTORY='$HIST' '$EXA' -u sys -P exasol -c '$CONN'"

wait_for_pane 'SQL_EXA>' 60

for ((i=0; i<${#QUERY}; i++)); do
  tmux send-keys -t "$SESSION:0.0" -l "${QUERY:$i:1}"
done

tmux send-keys -t "$SESSION:0.0" -H 3b
tmux send-keys -t "$SESSION:0.0" Enter

wait_for_pane '2 rows in resultset\.|1 row in resultset\.' 60
wait_for_pane 'SQL_EXA>' 60

pane="$(tmux capture-pane -J -p -t "$SESSION:0.0")"
count="$(printf '%s\n' "$pane" | { grep -o 'SQL_EXA> SELECT TABLE_NAME FROM EXA_ALL_TABLES WHERE' || true; } | wc -l | tr -d ' ')"
if [ "$count" -gt 1 ]; then
  echo "Wrapped input was redrawn repeatedly ($count matches)" >&2
  printf '%s\n' "$pane" >&2
  exit 1
fi

printf '%s\n' "$pane" | grep -q 'LINEITEM'
printf '%s\n' "$pane" | grep -q 'ORDERS'
printf '%s\n' "$pane" | grep -Eq '2 rows in resultset\.|1 row in resultset\.'

echo "OK"
