#!/usr/bin/env bash
# umcode start — rent GPU, provision instance, connect tunnel, start local stack.
# Run from repo directory (or via umcode start). Requires config.env with VAST_API_KEY.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

info()  { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }

source "${SCRIPT_DIR}/config.env"
[[ -z "${VAST_API_KEY:-}" ]] && fail "VAST_API_KEY is not set in config.env"

if ! command -v vastai &>/dev/null; then
  fail "vastai CLI not found. Install: pip install vastai"
fi
vastai set api-key "$VAST_API_KEY" >/dev/null 2>&1

mkdir -p "${SCRIPT_DIR}/workspace"

if [[ -f "${SCRIPT_DIR}/.instance_id" ]]; then
  INSTANCE_ID=$(cat "${SCRIPT_DIR}/.instance_id")
  info "Using existing instance ${INSTANCE_ID}"
else
  echo
  info "Searching for GPU offers (2× RTX Pro 6000, ~192GB VRAM)..."
  "${SCRIPT_DIR}/scripts/select-offer.sh" || fail "Offer selection failed"
  OFFER_ID=$(cat "${SCRIPT_DIR}/.selected_offer" 2>/dev/null)
  rm -f "${SCRIPT_DIR}/.selected_offer"
  [[ -z "${OFFER_ID:-}" ]] && fail "No offer selected."
  info "Provisioning Vast.ai instance (this may take a few minutes)..."
  "${SCRIPT_DIR}/provision.sh" "$OFFER_ID" || fail "provision failed"
  INSTANCE_ID=$(cat "${SCRIPT_DIR}/.instance_id")
  ok "Instance ${INSTANCE_ID} created. View at: https://cloud.vast.ai/instances/"
fi

info "Connecting SSH tunnel and waiting for model (5–10 min first time)..."
"${SCRIPT_DIR}/connect.sh" || fail "connect failed"

info "Starting local stack (docker compose up -d)..."
docker compose up -d || fail "docker compose up failed"
ok "Stack is up"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Ready. Run:  umcode opencode  |  umcode claude  |  umcode vscode --both"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
printf '\033[1;31m'
echo "To stop billing when done:  umcode destroy"
printf '\033[0m'
echo
