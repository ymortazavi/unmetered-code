#!/bin/bash
set -e

# Attach VS Code to a running container. We try two URI formats because behavior
# varies by VS Code/Dev Containers version and OS: (1) hex(container name) then (2) hex(JSON).
# See: https://cspotcode.com/posts/attach-vscode-to-container-from-cli
#      https://github.com/microsoft/vscode-remote-release/issues/8764
open_vscode() {
  local container="$1"
  local folder="$2"
  local docker_name
  docker_name=$(docker inspect -f '{{.Name}}' "$container" 2>/dev/null)
  if [[ -z "$docker_name" ]]; then
    echo "Error: Could not get name for container '${container}'."
    exit 1
  fi
  # Docker returns name with leading slash (e.g. /opencode-unmetered-code)
  local hex_name
  hex_name=$(printf '%s' "$docker_name" | xxd -p | tr -d '\n')
  local auth="attached-container+${hex_name}"
  echo "Opening VS Code attached to '${docker_name}' at ${folder} ..."
  echo "Tip: If the container is recreated (e.g. after docker compose down/up), run this script again."
  # Use only --folder-uri; some setups ignore or mishandle --remote and then show the picker.
  code --folder-uri "vscode-remote://${auth}${folder}"
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

Attach VS Code to the running agent containers ( You must have the Dev Containers extension installed in VS Code)
After attaching to the correct container, you can open the folder /workspace and open an integrated terminal.

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
