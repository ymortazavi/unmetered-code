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

# Colors
c_cyan='\033[1;36m'
c_green='\033[1;32m'
c_yellow='\033[1;33m'
c_red='\033[1;31m'
c_reset='\033[0m'
header() { printf "${c_cyan}%s${c_reset}\n" "$*"; }
warn()   { printf "${c_yellow}%s${c_reset}\n" "$*" >&2; }
fail()   { printf "${c_red}%s${c_reset}\n" "$*" >&2; exit 1; }

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

printf "  ${c_cyan}Prompt:${c_reset}  %s\n" "\"$PROMPT\""
printf "  ${c_cyan}Timeout:${c_reset} %ss per agent\n" "$TIMEOUT"
printf "  ${c_cyan}Mode:${c_reset}    %s\n" "$($PARALLEL && echo 'parallel' || echo 'sequential')"
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

  wait $pid_open 2>/dev/null || true
  wait $pid_claude 2>/dev/null || true

  echo ""
  header "--- OpenCode ---"
  cat "$OPENCODE_TIME"
  cat "$OPENCODE_OUT"
  echo ""
  header "--- Claude Code ---"
  cat "$CLAUDE_TIME"
  cat "$CLAUDE_OUT"
else
  header "=== OpenCode ==="
  time ( run_one opencode 'read -r p; opencode run "$p"' ) 2>&1 || true

  echo ""
  header "=== Claude Code ==="
  time ( run_one claude 'read -r p; exec claude --model minimax-m2.5 --dangerously-skip-permissions -p "$p"' ) 2>&1 || true
fi
