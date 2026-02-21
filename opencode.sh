#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${SCRIPT_DIR}/workspace"

cd "$SCRIPT_DIR"
if ! docker compose ps --status running -q opencode &>/dev/null; then
  echo "Error: Service 'opencode' is not running."
  echo "Start the stack first:  docker compose up -d"
  exit 1
fi

exec docker compose exec -it opencode bash -c 'cd /workspace && exec opencode "$@"' _ "$@"
