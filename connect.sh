#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

info()  { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Vast.ai Connector (SSH tunnel)"
echo "  Instance: ${INSTANCE_ID}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

info "Fetching instance details..."

RAW=$(vastai show instance "$INSTANCE_ID" --raw 2>/dev/null) \
  || fail "Could not fetch instance ${INSTANCE_ID}"

STATUS=$(echo "$RAW" | python3 -c "import sys,json; print(json.load(sys.stdin).get('actual_status','unknown'))" 2>/dev/null)
PUBLIC_IP=$(echo "$RAW" | python3 -c "import sys,json; print(json.load(sys.stdin).get('public_ipaddr',''))" 2>/dev/null)

SSH_PUBLIC_PORT=$(echo "$RAW" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ports = d.get('ports', {})
target = '22/tcp'
if target in ports:
    print(ports[target][0]['HostPort'])
else:
    print('')
" 2>/dev/null)

echo "  Status:    ${STATUS}"
echo "  Public IP: ${PUBLIC_IP:-not available}"
echo "  SSH port:  ${SSH_PUBLIC_PORT:-not available}"
echo

if [[ "$STATUS" != "running" ]]; then
  warn "Instance is not running (status: ${STATUS})"
  warn "Wait for the instance to fully start, then re-run this script."
  exit 1
fi

if [[ -z "$PUBLIC_IP" || -z "$SSH_PUBLIC_PORT" ]]; then
  fail "Could not determine public IP or SSH port mapping"
fi

# ──── Test SSH connectivity ──────────────────────────────

info "Testing SSH connectivity to ${PUBLIC_IP}:${SSH_PUBLIC_PORT}..."

if ssh -o ConnectTimeout=10 \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile=/dev/null \
      -o BatchMode=yes \
      -p "$SSH_PUBLIC_PORT" \
      "root@${PUBLIC_IP}" \
      "echo ok" 2>/dev/null | grep -q ok; then
  ok "SSH connection verified"
else
  warn "SSH not ready yet (instance may still be starting)"
  warn "Writing .env anyway — re-run connect.sh once SSH is up."
fi

# ──── Write .env for Docker Compose ──────────────────────

cat > "${SCRIPT_DIR}/.env" <<EOF
LLAMA_API_BASE=http://ssh-tunnel:${LLAMA_PORT}/v1
SSH_HOST=${PUBLIC_IP}
SSH_PORT=${SSH_PUBLIC_PORT}
REMOTE_PORT=${LLAMA_PORT}
EOF

ok "Wrote .env"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Connection configured!"
echo
echo "  SSH endpoint:    ${PUBLIC_IP}:${SSH_PUBLIC_PORT}"
echo "  Tunnel:          localhost:${LLAMA_PORT}  →ssh→  vast:${LLAMA_PORT}"
echo "  LiteLLM backend: http://ssh-tunnel:${LLAMA_PORT}/v1"
echo
echo "  Start local services:"
echo "    docker compose up -d --build"
echo
echo "  Verify tunnel (after compose up):"
echo "    docker exec ssh-tunnel-unmetered-code nc -z localhost ${LLAMA_PORT}"
echo
echo "  SSH into instance:"
echo "    ssh -p ${SSH_PUBLIC_PORT} root@${PUBLIC_IP}"
echo
echo "  View logs:"
echo "    vastai logs ${INSTANCE_ID}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
