#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

info()  { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }

source "${SCRIPT_DIR}/config.env"
[[ -z "${VAST_API_KEY:-}" ]] && fail "VAST_API_KEY is not set in config.env"

if ! command -v vastai &>/dev/null; then
  fail "vastai CLI not found. Install: pip install vastai"
fi

vastai set api-key "$VAST_API_KEY" > /dev/null 2>&1

INSTANCE_ID="${1:-}"
if [[ -z "$INSTANCE_ID" && -f "${SCRIPT_DIR}/.instance_id" ]]; then
  INSTANCE_ID=$(cat "${SCRIPT_DIR}/.instance_id")
fi
[[ -z "$INSTANCE_ID" ]] && fail "No instance ID. Pass as argument or run provision.sh first."

echo
info "Destroying instance ${INSTANCE_ID}..."

vastai destroy instance "$INSTANCE_ID" || fail "Failed to destroy instance"

ok "Instance ${INSTANCE_ID} destroyed"

rm -f "${SCRIPT_DIR}/.instance_id"
rm -f "${SCRIPT_DIR}/.env"

ok "Cleaned up .instance_id and .env"
echo
