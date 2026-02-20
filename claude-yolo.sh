#!/bin/bash
set -e

CONTAINER="claude-code-unmetered-code"

if ! docker inspect --format='{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
  echo "Error: Container '$CONTAINER' is not running."
  echo "Start the stack first:  docker compose up -d --build"
  exit 1
fi

exec docker exec -it "$CONTAINER" claude \
  --model minimax-m2.5 \
  --dangerously-skip-permissions \
  "$@"
