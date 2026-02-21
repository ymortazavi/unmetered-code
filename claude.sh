#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${SCRIPT_DIR}/workspace"

cd "$SCRIPT_DIR"
if ! docker compose ps --status running -q claude &>/dev/null; then
  echo "Error: Service 'claude' is not running."
  echo "Start the stack first:  docker compose up -d"
  exit 1
fi

exec docker compose exec -it claude bash -c 'cd /workspace && exec claude --model minimax-m2.5 "$@"' _ "$@"
