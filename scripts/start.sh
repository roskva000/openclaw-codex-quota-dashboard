#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

PIDFILE="$ROOT_DIR/dashboard.pid"
LOGFILE="$ROOT_DIR/dashboard.log"
PORT="${PORT:-8787}"
BIND_HOST="${BIND_HOST:-auto}"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Dashboard already running (pid $(cat "$PIDFILE"))"
  exit 0
fi

nohup env PORT="$PORT" BIND_HOST="$BIND_HOST" python3 "$ROOT_DIR/server.py" >> "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"
echo "Started dashboard pid $(cat "$PIDFILE")"
