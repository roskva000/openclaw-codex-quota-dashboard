#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDFILE="$ROOT_DIR/dashboard.pid"

if [[ ! -f "$PIDFILE" ]]; then
  echo "No pid file"
  exit 0
fi

PID="$(cat "$PIDFILE")"
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "Stopped pid $PID"
else
  echo "Process not running"
fi
rm -f "$PIDFILE"
