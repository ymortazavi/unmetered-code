#!/usr/bin/env bash
# GPU offer selector: uses fzf when available and TTY (no flicker), else first offer.
# Writes selected OFFER_ID to .selected_offer. Run from repo root (sources config.env).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=../config.env
source "${REPO_ROOT}/config.env"
[[ -z "${VAST_API_KEY:-}" ]] && { echo "VAST_API_KEY is not set in config.env" >&2; exit 1; }
command -v vastai &>/dev/null || { echo "vastai CLI not found" >&2; exit 1; }
vastai set api-key "$VAST_API_KEY" >/dev/null 2>&1

# Fetch offers (same query as install/start)
RAW=$(vastai search offers 'gpu_name in [RTX_PRO_6000_S,RTX_PRO_6000_WS] num_gpus==2 reliability>0.9' -o dph 2>/dev/null) || true
[[ -z "$RAW" ]] && { echo "No offers returned from vastai" >&2; exit 1; }

# Parse: first line = header, lines starting with digits = data (first column = ID)
HEADER=""
declare -a OFFER_IDS
declare -a LINES
while IFS= read -r line; do
  if [[ "$line" =~ ^[[:space:]]*([0-9]+)(.*) ]]; then
    OFFER_IDS+=("${BASH_REMATCH[1]}")
    LINES+=("$line")
  elif [[ -z "$HEADER" && -n "$line" ]]; then
    HEADER="$line"
  fi
done <<< "$RAW"

N=${#OFFER_IDS[@]}
[[ "$N" -eq 0 ]] && { echo "No offer rows found" >&2; exit 1; }

OUTFILE="${REPO_ROOT}/.selected_offer"

# Use fzf when we have a TTY and fzf is installed (stable, no flicker)
if [[ -t 1 ]] && command -v fzf &>/dev/null; then
  SELECTED=$(
    {
      printf '%s\n' "$HEADER"
      for (( i = 0; i < N; i++ )); do
        printf '%s\t%s\n' "${OFFER_IDS[$i]}" "${LINES[$i]}"
      done
    } | fzf --header-lines=1 --height=20 --reverse --tiebreak=index 2>/dev/null
  ) || true
  if [[ -n "$SELECTED" ]]; then
    echo "$SELECTED" | cut -f1 > "$OUTFILE"
    exit 0
  fi
fi

# Fallback: first offer (no fzf, or cancelled, or non-TTY)
echo "${OFFER_IDS[0]}" > "$OUTFILE"
