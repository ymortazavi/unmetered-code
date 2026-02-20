#!/bin/bash
set -e

hex_encode() {
  printf '%s' "$1" | xxd -p | tr -d '\n'
}

open_vscode() {
  local container="$1"
  local folder="$2"
  local hex_name
  hex_name=$(hex_encode "$container")
  echo "Opening VS Code attached to '${container}' at ${folder} ..."
  code --folder-uri "vscode-remote://attached-container+${hex_name}${folder}"
}

check_container() {
  if ! docker inspect --format='{{.State.Running}}' "$1" 2>/dev/null | grep -q true; then
    echo "Error: Container '$1' is not running."
    echo "Start the stack first:  cd unmetered-code && docker compose up -d --build"
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTION]

Attach VS Code to the running agent containers.

Options:
  --opencode   Open only the OpenCode container
  --claude     Open only the Claude Code container
  --both       Open both containers (default)
  -h, --help   Show this help message
EOF
}

TARGET="both"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --opencode) TARGET="opencode"; shift ;;
    --claude)   TARGET="claude"; shift ;;
    --both)     TARGET="both"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

case "$TARGET" in
  opencode)
    check_container "opencode-unmetered-code"
    open_vscode "opencode-unmetered-code" "/workspace"
    ;;
  claude)
    check_container "claude-code-unmetered-code"
    open_vscode "claude-code-unmetered-code" "/workspace"
    ;;
  both)
    check_container "opencode-unmetered-code"
    check_container "claude-code-unmetered-code"
    open_vscode "opencode-unmetered-code" "/workspace"
    sleep 1
    open_vscode "claude-code-unmetered-code" "/workspace"
    ;;
esac

echo "Done. Use the integrated terminal in each VS Code window to run the agent."
