#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
fi

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
PROVIDER="${PROVIDER:-openai-codex}"
AGENT="${AGENT_ID:-quota}"
AGENT_DIR="${OPENCLAW_AGENT_DIR_OVERRIDE:-$HOME/.openclaw/agents/${AGENT}/agent}"
OUTPUT_JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) PROVIDER="${2:-}"; shift 2 ;;
    --agent) AGENT="${2:-}"; AGENT_DIR="${OPENCLAW_AGENT_DIR_OVERRIDE:-$HOME/.openclaw/agents/${AGENT}/agent}"; shift 2 ;;
    --json) OUTPUT_JSON=1; shift ;;
    -h|--help)
      cat <<HELP
Usage: $(basename "$0") [--provider <id>] [--agent <id>] [--json]
Defaults: provider=${PROVIDER}, agent=${AGENT}
HELP
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

require(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
require "$OPENCLAW_BIN"; require jq; require date

fetch_channels_json() {
  local i out
  for i in 1 2 3; do
    if out="$(OPENCLAW_AGENT_DIR="$AGENT_DIR" PI_CODING_AGENT_DIR="$AGENT_DIR" "$OPENCLAW_BIN" channels list --json 2>/dev/null)"; then
      echo "$out"; return 0
    fi
    sleep "$i"
  done
  return 1
}

if ! channels_json="$(fetch_channels_json)"; then
  echo "Failed to read channels usage after retries." >&2
  exit 3
fi

profiles=($(jq -r --arg p "$PROVIDER" '.auth[] | select(.provider==$p) | .id' <<<"$channels_json"))
[[ ${#profiles[@]} -gt 0 ]] || { echo "No auth profiles found for provider: $PROVIDER" >&2; exit 2; }

order_json="$("$OPENCLAW_BIN" models auth order get --agent "$AGENT" --provider "$PROVIDER" --json 2>/dev/null || true)"
orig_order=()
if [[ -n "$order_json" ]] && jq -e '.order and (.order|type=="array")' >/dev/null 2>&1 <<<"$order_json"; then
  while IFS= read -r id; do [[ -n "$id" ]] && orig_order+=("$id"); done < <(jq -r '.order[]' <<<"$order_json")
fi
[[ ${#orig_order[@]} -gt 0 ]] || orig_order=("${profiles[@]}")

restore(){ "$OPENCLAW_BIN" models auth order set --agent "$AGENT" --provider "$PROVIDER" "${orig_order[@]}" >/dev/null 2>&1 || true; }
trap restore EXIT

results='[]'
for profile in "${profiles[@]}"; do
  "$OPENCLAW_BIN" models auth order set --agent "$AGENT" --provider "$PROVIDER" "$profile" >/dev/null
  if ! usage_json="$(fetch_channels_json)"; then
    usage_json='{"usage":{"providers":[]}}'
  fi

  plan="$(jq -r --arg p "$PROVIDER" 'first(.usage.providers[]? | select(.provider==$p) | .plan) // "unknown"' <<<"$usage_json")"
  windows="$(jq -c --arg p "$PROVIDER" '[.usage.providers[]? | select(.provider==$p) | .windows[]? | {label:.label, usedPercent:.usedPercent, remainingPercent:(100-(.usedPercent//0)), resetAt:.resetAt}]' <<<"$usage_json")"

  results="$(jq -cn --argjson arr "$results" --arg profile "$profile" --arg plan "$plan" --argjson windows "$windows" '$arr + [{profile:$profile, plan:$plan, windows:$windows}]')"
done

orig_order_json="$(printf '%s\n' "${orig_order[@]}" | jq -R . | jq -s .)"
report="$(jq -cn --arg provider "$PROVIDER" --arg agent "$AGENT" --arg generatedAt "$(date -Iseconds)" --argjson originalOrder "$orig_order_json" --argjson profiles "$results" '{provider:$provider, agent:$agent, generatedAt:$generatedAt, originalOrder:$originalOrder, profiles:$profiles}')"

if [[ $OUTPUT_JSON -eq 1 ]]; then
  echo "$report" | jq .
  exit 0
fi

echo "Provider : $(jq -r '.provider' <<<"$report")"
echo "Agent    : $(jq -r '.agent' <<<"$report")"
echo "Generated: $(jq -r '.generatedAt' <<<"$report")"
echo "Order    : $(jq -r '.originalOrder | join(" -> ")' <<<"$report")"
echo
for profile in "${profiles[@]}"; do
  echo "[$profile]"
  jq -r --arg p "$profile" '.profiles[] | select(.profile==$p) | if (.windows|length)==0 then "  usage: unavailable" else .windows[] | "  \(.label): used \(.usedPercent)% | left \(.remainingPercent)% | reset " + ((.resetAt//0)/1000 | strftime("%Y-%m-%d %H:%M:%S %Z")) end' <<<"$report"
  echo
done

echo "Done. Original auth order restored."
