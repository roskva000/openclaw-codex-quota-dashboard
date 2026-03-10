#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

[[ -f .env ]] || cp .env.example .env
# shellcheck disable=SC1091
source .env

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
PROVIDER="${PROVIDER:-openai-codex}"
AGENT_ID="${AGENT_ID:-quota}"
CREATE_AGENT="${CREATE_AGENT:-1}"
MODEL_ID="${MODEL_ID:-openai-codex/gpt-5.3-codex}"
AGENT_WORKSPACE="${AGENT_WORKSPACE:-agent-workspace}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need "$OPENCLAW_BIN"; need jq; need python3

if [[ "$AGENT_WORKSPACE" != /* ]]; then
  AGENT_WORKSPACE="$ROOT_DIR/$AGENT_WORKSPACE"
fi
mkdir -p "$AGENT_WORKSPACE" "$ROOT_DIR/data"
ln -sfn ../data "$ROOT_DIR/public/data"

if [[ "$CREATE_AGENT" == "1" ]]; then
  if ! "$OPENCLAW_BIN" agents list --json | jq -e --arg id "$AGENT_ID" '.[] | select(.id==$id)' >/dev/null; then
    echo "Creating isolated agent: $AGENT_ID"
    "$OPENCLAW_BIN" agents add "$AGENT_ID" --non-interactive --workspace "$AGENT_WORKSPACE" --model "$MODEL_ID" >/dev/null
  else
    echo "Agent exists: $AGENT_ID"
  fi
fi

bash "$ROOT_DIR/scripts/codex-quota-collector.sh"

CRON_TAG="# codex-quota-dashboard-kit"
CURRENT_CRON="$(crontab -l 2>/dev/null | grep -v 'codex-quota-dashboard-kit' || true)"
{
  echo "$CURRENT_CRON"
  echo "@reboot /usr/bin/env bash $ROOT_DIR/scripts/start.sh >> $ROOT_DIR/dashboard.log 2>&1 $CRON_TAG"
} | awk 'NF && !seen[$0]++' | crontab -

bash "$ROOT_DIR/scripts/start.sh"

if [[ "${BIND_HOST:-auto}" == "auto" ]]; then
  HOST="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  [[ -n "$HOST" ]] || HOST="127.0.0.1"
else
  HOST="$BIND_HOST"
fi
PORT="${PORT:-8787}"

echo
echo "✅ Installed"
echo "Open: http://$HOST:$PORT"
echo "Config: $ROOT_DIR/.env"
