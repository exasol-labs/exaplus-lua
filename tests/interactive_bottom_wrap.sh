#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
EXA="${EXAPLUS_BIN:-$DIR/../exaplus}"
HOST="${EXAPLUS_TEST_HOST:-localhost}"
PORT="${EXAPLUS_TEST_PORT:-8563}"
CONN="$HOST/nocertcheck:$PORT"
SESSION="exaplus_bottom_wrap_test_$$"
KH="/tmp/exaplus_known_hosts_bottom_wrap_$$"
HIST="/tmp/exaplus_history_bottom_wrap_$$"
COLS=72
ROWS=10
QUERY1="SELECT TABLE_NAME FROM EXA_ALL_TABLES WHERE TABLE_SCHEMA = 'TPC' AND TABLE_NAME IN ('LINEITEM', 'ORDERS', 'CUSTOMER', 'PARTSUPP', 'SUPPLIER', 'NATION', 'REGION') ORDER BY TABLE_NAME"
QUERY2="SELECT COLUMN_NAME FROM EXA_ALL_COLUMNS WHERE COLUMN_SCHEMA = 'TPC' AND COLUMN_TABLE IN ('LINEITEM', 'ORDERS') ORDER BY COLUMN_TABLE, COLUMN_ORDINAL_POSITION"

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  rm -f "$KH" "$HIST"
}
trap cleanup EXIT

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP interactive_bottom_wrap.sh (tmux not installed)"
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

type_query() {
  local q="$1"
  for ((i=0; i<${#q}; i++)); do
    tmux send-keys -t "$SESSION:0.0" -l "${q:$i:1}"
  done
}

submit_query() {
  tmux send-keys -t "$SESSION:0.0" -H 3b
  tmux send-keys -t "$SESSION:0.0" Enter
}

tmux new-session -d -x "$COLS" -y "$ROWS" -s "$SESSION" \
  "env COLUMNS=$COLS LINES=$ROWS EXAPLUS_KNOWN_HOSTS='$KH' EXAPLUS_HISTORY='$HIST' '$EXA' -u sys -P exasol -c '$CONN'"

wait_for_pane 'SQL_EXA>' 60

type_query "$QUERY1"
submit_query
wait_for_pane '7 rows in resultset\.' 60
wait_for_pane 'SQL_EXA>' 60

type_query "$QUERY2"
pane="$(tmux capture-pane -J -p -t "$SESSION:0.0")"

printf '%s\n' "$pane" | grep -q '^7 rows in resultset\.$'
printf '%s\n' "$pane" | grep -q 'SQL_EXA> SELECT COLUMN_NAME FROM EXA_ALL_COLUMNS WHERE COLUMN_SCHEMA'
printf '%s\n' "$pane" | grep -q "COLUMN_TABLE IN ('LINEITEM', 'ORDERS')"
printf '%s\n' "$pane" | grep -q 'ORDINAL_POSITION'
if printf '%s\n' "$pane" | grep -q 'AC:ON'; then
  echo "Inline status line should not be rendered by default" >&2
  printf '%s\n' "$pane" >&2
  exit 1
fi

echo "OK"
