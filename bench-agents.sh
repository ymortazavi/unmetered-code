#!/usr/bin/env bash
# Benchmark: run a small prompt through OpenCode and Claude Code, report time.
# Requires: docker compose up -d (stack running)
#
# Usage: ./bench-agents.sh [options] [prompt]
#   -p, --parallel    Run both agents in parallel (default: sequential)
#   [prompt]          Prompt to send (default: "hi")
#
# Example: ./bench-agents.sh "build a python terminal based snake app with a unique name"
#          ./bench-agents.sh -p "build a python terminal based snake app with a unique name"
# Timeout: BENCH_TIMEOUT=120 (default 90). Install coreutils for timeout: brew install coreutils

set -e
cd "$(dirname "$0")"

# Colors and styling
c_cyan='\033[1;36m'
# shellcheck disable=SC2034  # used in printf for "✓ Benchmark complete"
c_green='\033[1;32m'
c_yellow='\033[1;33m'
c_red='\033[1;31m'
c_dim='\033[2m'
c_time='\033[1;35m'   # magenta for elapsed time
c_reset='\033[0m'
rule="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
header()  { printf '%b\n' "${c_cyan}$*${c_reset}"; }
warn()    { printf '%b\n' "${c_yellow}$*${c_reset}" >&2; }
fail()    { printf '%b\n' "${c_red}$*${c_reset}" >&2; exit 1; }
box()     { printf '%b\n' "  ${c_cyan}┌─ $1 ─${rule:0:$((44-${#1}))}┐${c_reset}"; }
box_end() { printf '%b\n' "  ${c_cyan}└${rule:0:48}┘${c_reset}"; }
# Extract "real" elapsed time from time(1) stderr (e.g. "0m41.797s")
time_real() { sed -n '/^real/s/^real[[:space:]]*//p' "$1"; }
# Print lines with cyan left border (│) to match box header/footer
box_body() { while IFS= read -r line; do printf '%b %s\n' "  ${c_cyan}│${c_reset}" "$line"; done; }
box_blank() { printf '  %b\n' "${c_cyan}│${c_reset}"; }

PARALLEL=false
PROMPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--parallel) PARALLEL=true; shift ;;
    -h|--help)
      head -20 "$0" | grep -E '^#'
      exit 0
      ;;
    *) PROMPT="$1"; shift ;;
  esac
done
PROMPT="${PROMPT:-hi}"
TIMEOUT="${BENCH_TIMEOUT:-90}"

# Resolve timeout command (GNU timeout or macOS gtimeout)
run_with_timeout() {
  if command -v timeout &>/dev/null; then
    timeout "$TIMEOUT" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$TIMEOUT" "$@"
  else
    warn "No 'timeout' command. Install coreutils (brew install coreutils) to avoid hangs."
    "$@"
  fi
}

# Check services
for svc in opencode claude; do
  if ! docker compose ps --status running -q "$svc" &>/dev/null; then
    fail "Error: service '$svc' is not running. Start the stack: docker compose up -d"
  fi
done

echo ""
printf '%b\n' "${c_cyan}${rule}${c_reset}"
printf '%b  Agent benchmark · %s%b\n' "${c_cyan}" "$("$PARALLEL" && echo 'parallel' || echo 'sequential')" "${c_reset}"
printf '%b\n' "${c_cyan}${rule}${c_reset}"
echo ""
printf '  %bPrompt:%b  %s\n' "${c_dim}" "${c_reset}" "\"$PROMPT\""
printf '  %bTimeout:%b %ss per agent\n' "${c_dim}" "${c_reset}" "$TIMEOUT"
echo ""

# Pass prompt via stdin to avoid quoting/argument issues with docker compose exec
run_one() {
  local service="$1"
  local cmd="$2"
  echo "$PROMPT" | run_with_timeout docker compose exec -T -i -w /workspace "$service" sh -c "$cmd"
}

if "$PARALLEL"; then
  OPENCODE_OUT=$(mktemp)
  OPENCODE_TIME=$(mktemp)
  CLAUDE_OUT=$(mktemp)
  CLAUDE_TIME=$(mktemp)
  trap 'rm -f "$OPENCODE_OUT" "$OPENCODE_TIME" "$CLAUDE_OUT" "$CLAUDE_TIME"' EXIT

  ( time ( run_one opencode 'read -r p; opencode run "$p"' ) ) 2> "$OPENCODE_TIME" > "$OPENCODE_OUT" &
  pid_open=$!
  ( time ( run_one claude 'read -r p; exec claude --model minimax-m2.5 --dangerously-skip-permissions -p "$p"' ) ) 2> "$CLAUDE_TIME" > "$CLAUDE_OUT" &
  pid_claude=$!

  wait "$pid_open" 2>/dev/null || true
  wait "$pid_claude" 2>/dev/null || true

  echo ""
  box "OpenCode"
  box_blank
  printf '  %b %bTime: %s%b\n' "${c_cyan}│${c_reset}" "${c_time}" "$(time_real "$OPENCODE_TIME")" "${c_reset}"
  box_blank
  box_body < "$OPENCODE_OUT"
  box_blank
  box_end
  echo ""
  echo ""
  box "Claude Code"
  box_blank
  printf '  %b %bTime: %s%b\n' "${c_cyan}│${c_reset}" "${c_time}" "$(time_real "$CLAUDE_TIME")" "${c_reset}"
  box_blank
  box_body < "$CLAUDE_OUT"
  box_blank
  box_end
  echo ""
  echo ""
  printf '%b\n' "${c_green}  ✓ Benchmark complete${c_reset}"
else
  OPENCODE_OUT=$(mktemp)
  OPENCODE_TIME=$(mktemp)
  CLAUDE_OUT=$(mktemp)
  CLAUDE_TIME=$(mktemp)
  trap 'rm -f "$OPENCODE_OUT" "$OPENCODE_TIME" "$CLAUDE_OUT" "$CLAUDE_TIME"' EXIT

  ( time ( run_one opencode 'read -r p; opencode run "$p"' ) ) 2> "$OPENCODE_TIME" > "$OPENCODE_OUT" || true
  ( time ( run_one claude 'read -r p; exec claude --model minimax-m2.5 --dangerously-skip-permissions -p "$p"' ) ) 2> "$CLAUDE_TIME" > "$CLAUDE_OUT" || true

  echo ""
  box "OpenCode"
  box_blank
  printf '  %b %bTime: %s%b\n' "${c_cyan}│${c_reset}" "${c_time}" "$(time_real "$OPENCODE_TIME")" "${c_reset}"
  box_blank
  box_body < "$OPENCODE_OUT"
  box_blank
  box_end
  echo ""
  echo ""
  box "Claude Code"
  box_blank
  printf '  %b %bTime: %s%b\n' "${c_cyan}│${c_reset}" "${c_time}" "$(time_real "$CLAUDE_TIME")" "${c_reset}"
  box_blank
  box_body < "$CLAUDE_OUT"
  box_blank
  box_end
  echo ""
  echo ""
  printf '%b\n' "${c_green}  ✓ Benchmark complete${c_reset}"
fi
