#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"
EXA_DEFAULT="$ROOT_DIR/exaplus"
EXAPLUS_BIN_ARG="${EXAPLUS_BIN:-}"
EXAPLUS_TEST_HOST_ARG="${EXAPLUS_TEST_HOST:-localhost}"
EXAPLUS_TEST_PORT_ARG="${EXAPLUS_TEST_PORT:-8563}"

usage() {
  echo "Usage: $0 [--static /path/to/exaplus] [--host host] [--port port]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --static)
      if [[ $# -lt 2 ]]; then
        echo "Missing path for --static" >&2
        usage >&2
        exit 2
      fi
      EXAPLUS_BIN_ARG="$2"
      shift 2
      ;;
    --host)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --host" >&2
        usage >&2
        exit 2
      fi
      EXAPLUS_TEST_HOST_ARG="$2"
      shift 2
      ;;
    --port)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --port" >&2
        usage >&2
        exit 2
      fi
      EXAPLUS_TEST_PORT_ARG="$2"
      if ! [[ "$EXAPLUS_TEST_PORT_ARG" =~ ^[0-9]+$ ]]; then
        echo "Invalid port: $EXAPLUS_TEST_PORT_ARG" >&2
        exit 2
      fi
      if [[ "$EXAPLUS_TEST_PORT_ARG" -lt 1 || "$EXAPLUS_TEST_PORT_ARG" -gt 65535 ]]; then
        echo "Port out of range: $EXAPLUS_TEST_PORT_ARG" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$EXAPLUS_TEST_HOST_ARG" == *:* ]]; then
  echo "Host must not include port; use --port" >&2
  exit 2
fi

export EXAPLUS_TEST_HOST="$EXAPLUS_TEST_HOST_ARG"
export EXAPLUS_TEST_PORT="$EXAPLUS_TEST_PORT_ARG"

if [[ -n "$EXAPLUS_BIN_ARG" ]]; then
  if [[ "$EXAPLUS_BIN_ARG" != /* ]]; then
    EXAPLUS_BIN_ARG="$(cd "$(dirname "$EXAPLUS_BIN_ARG")" && pwd)/$(basename "$EXAPLUS_BIN_ARG")"
  fi
  if [[ ! -x "$EXAPLUS_BIN_ARG" ]]; then
    echo "Static binary not found or not executable: $EXAPLUS_BIN_ARG" >&2
    exit 2
  fi
  export EXAPLUS_BIN="$EXAPLUS_BIN_ARG"
fi

EXA="${EXAPLUS_BIN_ARG:-$EXA_DEFAULT}"

HOST="$EXAPLUS_TEST_HOST_ARG"
PORT="$EXAPLUS_TEST_PORT_ARG"
HOSTPORT="$HOST:$PORT"
CONN_HOST="$HOST"
if [[ "$PORT" != "8563" ]]; then
  CONN_HOST="$HOSTPORT"
fi
HOST_NC="$HOST/nocertcheck:$PORT"

PREP_TMPDIR=$(mktemp -d)
KH="$PREP_TMPDIR/known_hosts"
if EXAPLUS_KNOWN_HOSTS="$KH" EXAPLUS_TEST_QUIET=1 "$EXA" -q -u sys -P exasol -c "$HOST_NC" -sql "SELECT 1;" >/dev/null 2>&1; then
  if [[ -z "${EXAPLUS_TEST_FINGERPRINT:-}" && -s "$KH" ]]; then
    fp=$(awk -v hp="$HOSTPORT" '$1==hp {print $2; exit}' "$KH")
    if [[ -n "$fp" ]]; then
      export EXAPLUS_TEST_FINGERPRINT="$fp"
    fi
  fi

  if out=$(EXAPLUS_KNOWN_HOSTS="$KH" EXAPLUS_TEST_QUIET=1 "$EXA" -q -u sys -P exasol -c "$CONN_HOST" -sql "SELECT SCHEMA_NAME FROM EXA_ALL_SCHEMAS WHERE SCHEMA_NAME='TEST2';" 2>/dev/null); then
    if ! echo "$out" | grep -qi "TEST2"; then
      EXAPLUS_KNOWN_HOSTS="$KH" EXAPLUS_TEST_QUIET=1 "$EXA" -q -u sys -P exasol -c "$CONN_HOST" -sql "CREATE SCHEMA test2;" >/dev/null 2>&1 || true
    fi
  fi
fi
rm -rf "$PREP_TMPDIR"

echo "RUN run.lua"
EXAPLUS_TEST_QUIET=1 lua "$DIR/run.lua"
echo "OK run.lua"

echo "RUN options_core.sh"
EXAPLUS_TEST_QUIET=1 "$DIR/options_core.sh"
echo "OK options_core.sh"

echo "RUN options_more.sh"
EXAPLUS_TEST_QUIET=1 "$DIR/options_more.sh"
echo "OK options_more.sh"

echo "RUN sql_scripts.sh"
EXAPLUS_TEST_QUIET=1 "$DIR/sql_scripts.sh"
echo "OK sql_scripts.sh"

echo "RUN autocommit_semantics.sh"
EXAPLUS_TEST_QUIET=1 "$DIR/autocommit_semantics.sh"
echo "OK autocommit_semantics.sh"

echo "RUN tpch_cases.sh"
EXAPLUS_TEST_QUIET=1 "$DIR/tpch_cases.sh"
echo "OK tpch_cases.sh"

echo "RUN tpch_sql_files.sh"
EXAPLUS_TEST_QUIET=1 "$DIR/tpch_sql_files.sh"
echo "OK tpch_sql_files.sh"

if command -v expect >/dev/null 2>&1; then
  echo "RUN interactive.expect"
  LOG="$DIR/interactive.expect.log"
  if ! expect "$DIR/interactive.expect" >"$LOG" 2>&1; then
    echo "interactive.expect failed, log:"
    tail -n 50 "$LOG"
    exit 1
  fi
  echo "OK interactive.expect"
else
  echo "SKIP interactive.expect (expect not installed)"
fi

if command -v tmux >/dev/null 2>&1; then
  echo "RUN interactive_wrap.sh"
  EXAPLUS_TEST_QUIET=1 "$DIR/interactive_wrap.sh"
  echo "OK interactive_wrap.sh"

  echo "RUN interactive_bottom_wrap.sh"
  EXAPLUS_TEST_QUIET=1 "$DIR/interactive_bottom_wrap.sh"
  echo "OK interactive_bottom_wrap.sh"
else
  echo "SKIP interactive_wrap.sh (tmux not installed)"
  echo "SKIP interactive_bottom_wrap.sh (tmux not installed)"
fi

echo "ALL OK"
