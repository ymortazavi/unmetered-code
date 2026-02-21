#!/usr/bin/env bash
# Interactive GPU offer selector: arrow keys to move, Enter to select.
# Outputs the selected OFFER_ID to stdout. Run from repo root (sources config.env).
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

# Output file for selected ID (caller reads this when interactive; stdout used for UI)
OUTFILE="${REPO_ROOT}/.selected_offer"

# If not a TTY, output first offer to stdout and exit (no interactive selection)
if ! [[ -t 0 ]]; then
  echo "${OFFER_IDS[0]}"
  exit 0
fi

# Truncate long lines for display (terminal width or 120)
COLS=${COLUMNS:-120}
[[ "$COLS" -gt 120 ]] && COLS=120
trim() { echo "${1:0:$COLS}"; }

# Selection state
SEL=0
# Colors: selected = reverse video
REV_ON=$'\033[7m'
REV_OFF=$'\033[0m'

draw() {
  local i
  printf '\r\033[K%s\n' "$HEADER"
  for (( i=0; i<N; i++ )); do
    if [[ $i -eq $SEL ]]; then
      printf '%b%s%b\n' "$REV_ON" "$(trim "${LINES[$i]}")" "$REV_OFF"
    else
      printf '%s\n' "$(trim "${LINES[$i]}")"
    fi
  done
  printf '\033[1;36m  ↑/↓ select  Enter confirm\033[0m\n'
}

# Save and set terminal for raw key reading
SAVED_STTY=""
if [[ -t 0 ]]; then
  SAVED_STTY=$(stty -g 2>/dev/null) || true
  stty -echo -icanon min 1 time 0 2>/dev/null || true
fi

# Initial draw
draw
LINES_DRAWN=$(( N + 2 ))  # header + N rows + hint

while true; do
  KEY=""
  read -rsn1 KEY
  if [[ "$KEY" == $'\033' ]]; then
    read -rsn2 KEY
    if [[ "$KEY" == "[A" ]]; then
      SEL=$(( SEL - 1 ))
      [[ $SEL -lt 0 ]] && SEL=0
    elif [[ "$KEY" == "[B" ]]; then
      SEL=$(( SEL + 1 ))
      [[ $SEL -ge $N ]] && SEL=$(( N - 1 ))
    fi
    # Redraw: move cursor up, then redraw all
    printf '\033[%dA' "$LINES_DRAWN"
    draw
  elif [[ "$KEY" == $'\r' || "$KEY" == $'\n' ]]; then
    break
  fi
done

# Restore terminal
[[ -n "$SAVED_STTY" ]] && stty "$SAVED_STTY" 2>/dev/null || true

# Move cursor down past the list so next output is clean
printf '\033[%dB\033[K\n' "$LINES_DRAWN" >/dev/tty

# Write selected ID to file for caller (stdout was used for UI)
echo "${OFFER_IDS[$SEL]}" > "$OUTFILE"
