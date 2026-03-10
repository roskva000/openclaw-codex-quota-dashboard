#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$ROOT_DIR/scripts/stop.sh" || true

crontab -l 2>/dev/null | grep -v 'codex-quota-dashboard-kit' | crontab - || true

echo "Removed startup cron entry and stopped dashboard."
echo "Project files kept at: $ROOT_DIR"
