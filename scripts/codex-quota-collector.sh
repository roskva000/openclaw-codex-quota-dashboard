#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

REFRESH_TIMEOUT="${REFRESH_TIMEOUT:-180}"
DATA_DIR="$ROOT_DIR/data"
LOCK_FILE="$ROOT_DIR/collector.lock"
mkdir -p "$DATA_DIR"

OUT="$DATA_DIR/latest.json"
TMP="$(mktemp "$DATA_DIR/latest.json.tmp.XXXXXX")"
cleanup(){ rm -f "$TMP"; }
trap cleanup EXIT

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "collector: skip (another run active)" >&2
  exit 0
fi

if ! timeout "$REFRESH_TIMEOUT" bash "$ROOT_DIR/scripts/codex-quota-report.sh" --json > "$TMP"; then
  echo "collector: report timed out/failed" >&2
  exit 1
fi

jq empty "$TMP" >/dev/null
mv -f "$TMP" "$OUT"
