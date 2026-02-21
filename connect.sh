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

VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    *) break ;;
  esac
done

INSTANCE_ID="${1:-}"
if [[ -z "$INSTANCE_ID" && -f "${SCRIPT_DIR}/.instance_id" ]]; then
  INSTANCE_ID=$(cat "${SCRIPT_DIR}/.instance_id")
fi
[[ -z "$INSTANCE_ID" ]] && fail "No instance ID. Pass as argument or run provision.sh first. Use -v to show recent instance logs."

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

# ──── Show recent instance logs (model download / llama-server) ───────────

if [[ "$VERBOSE" -eq 1 ]]; then
  info "Recent instance logs (model download / startup):"
  echo "  ┌────────────────────────────────────────────────────────────────────"
  if LOGS=$(vastai logs "$INSTANCE_ID" 2>/dev/null); then
    echo "$LOGS" | tail -40 | sed 's/^/  │ /'
  else
    echo "  │ (could not fetch logs — instance may still be starting)"
  fi
  echo "  └────────────────────────────────────────────────────────────────────"
  echo
fi

if [[ "$STATUS" != "running" ]]; then
  warn "Instance is not running (status: ${STATUS})"
  warn "Wait for the instance to fully start, then re-run this script."
  exit 1
fi

if [[ -z "$PUBLIC_IP" || -z "$SSH_PUBLIC_PORT" ]]; then
  fail "Could not determine public IP or SSH port mapping"
fi

# SSH connection options (reused for wait loops)
SSH_OPTS=(-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
  -p "$SSH_PUBLIC_PORT" "root@${PUBLIC_IP}")

# ──── Wait for SSH, then model ready flag, then llama-server port ─────────

info "Waiting for SSH (instance may still be booting)..."
SSH_MAX_WAIT=600   # 10 min
SSH_ELAPSED=0
while ! ssh "${SSH_OPTS[@]}" "echo ok" 2>/dev/null | grep -q ok; do
  sleep 10
  SSH_ELAPSED=$((SSH_ELAPSED + 10))
  if [[ $SSH_ELAPSED -ge $SSH_MAX_WAIT ]]; then
    fail "SSH did not become ready within ${SSH_MAX_WAIT}s. Re-run connect.sh later."
  fi
  printf '\r  %ds elapsed...' "$SSH_ELAPSED"
done
printf '\r'
ok "SSH connection verified"

READY_FLAG="/workspace/llama.cpp/models/.download_complete"
LLAMA_PORT_REMOTE="${LLAMA_PORT:-8080}"

info "Waiting for model download to complete (this can take 5–10 min)..."
DOWNLOAD_MAX_WAIT=7200   # 2 hr
DOWNLOAD_ELAPSED=0
while ! ssh "${SSH_OPTS[@]}" "test -f $READY_FLAG" 2>/dev/null; do
  sleep 30
  DOWNLOAD_ELAPSED=$((DOWNLOAD_ELAPSED + 30))
  if [[ $DOWNLOAD_ELAPSED -ge $DOWNLOAD_MAX_WAIT ]]; then
    fail "Model download did not complete within $((DOWNLOAD_MAX_WAIT / 60)) minutes. Check: vastai logs $INSTANCE_ID"
  fi
  printf '\r  %d min elapsed...' "$((DOWNLOAD_ELAPSED / 60))"
done
printf '\r'
ok "Model download complete"

info "Waiting for llama-server to listen on port ${LLAMA_PORT_REMOTE}..."
LLAMA_MAX_WAIT=300   # 5 min
LLAMA_ELAPSED=0
PORT_CHECK="python3 -c \"import socket; s=socket.socket(); s.settimeout(2); s.connect(('127.0.0.1',$LLAMA_PORT_REMOTE)); s.close()\""
while ! ssh "${SSH_OPTS[@]}" "$PORT_CHECK" 2>/dev/null; do
  sleep 5
  LLAMA_ELAPSED=$((LLAMA_ELAPSED + 5))
  if [[ $LLAMA_ELAPSED -ge $LLAMA_MAX_WAIT ]]; then
    fail "llama-server did not start within $((LLAMA_MAX_WAIT / 60)) minutes. Check: vastai logs $INSTANCE_ID"
  fi
  printf '\r  %ds elapsed...' "$LLAMA_ELAPSED"
done
printf '\r'
ok "llama-server is ready"
echo

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
echo "  Start local services (required before verify):"
echo "    docker compose up -d"
echo "  On Apple Silicon (arm64), build from source instead (first run: 2–5+ min build):"
echo "    docker compose -f compose.yaml -f compose.build.yaml up -d --build"
echo
echo "  Then verify tunnel (no output = success; any error message = tunnel not ready):"
echo "    docker compose exec ssh-tunnel nc -z 127.0.0.1 ${LLAMA_PORT}"
echo
echo "  SSH into instance:"
echo "    ssh -p ${SSH_PUBLIC_PORT} root@${PUBLIC_IP}"
echo
echo "  View logs:"
echo "    vastai logs ${INSTANCE_ID}"
echo "    (or run connect.sh with -v to show recent logs)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
