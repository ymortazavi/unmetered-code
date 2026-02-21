#!/usr/bin/env bash
# GPU offer selector: uses Python curses when available and TTY, else first offer.
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

# Prefer Python curses selector when stdout is a TTY and python3 is available
if [[ -t 1 ]] && command -v python3 &>/dev/null; then
  # Stream: header, then "ID\tdisplay_line" per row
  {
    printf '%s\n' "$HEADER"
    for (( i = 0; i < N; i++ )); do
      printf '%s\t%s\n' "${OFFER_IDS[$i]}" "${LINES[$i]}"
    done
  } | python3 "${SCRIPT_DIR}/select_offer.py" "$OUTFILE" 2>/dev/null && [[ -s "$OUTFILE" ]] && exit 0
fi

# Fallback: write first offer
echo "${OFFER_IDS[0]}" > "$OUTFILE"
