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

MODEL_DIR="/workspace/llama.cpp/models"

TOTAL_BYTES=0
TOTAL_HUMAN=""
if [[ -n "${HF_REPO:-}" && -n "${HF_QUANT:-}" ]] && command -v curl &>/dev/null; then
  IFS=' ' read -r TOTAL_BYTES TOTAL_HUMAN < <(
    curl -sL "https://huggingface.co/api/models/${HF_REPO}/tree/main/${HF_QUANT}" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    files = json.load(sys.stdin)
    total = sum(f.get('size', 0) for f in files if isinstance(f, dict))
    if total >= 1073741824:
        print(total, f'{total/1073741824:.0f}G')
    elif total > 0:
        print(total, f'{total/1048576:.0f}M')
except: pass" 2>/dev/null
  ) || true
  TOTAL_BYTES="${TOTAL_BYTES:-0}"
fi

info "Waiting for model download to complete (this can take 5–10 min)..."
DOWNLOAD_MAX_WAIT=7200   # 2 hr
DOWNLOAD_ELAPSED=0
PREV_BYTES=0
while ! ssh "${SSH_OPTS[@]}" "test -f $READY_FLAG" 2>/dev/null; do
  sleep 30
  DOWNLOAD_ELAPSED=$((DOWNLOAD_ELAPSED + 30))
  if [[ $DOWNLOAD_ELAPSED -ge $DOWNLOAD_MAX_WAIT ]]; then
    fail "Model download did not complete within $((DOWNLOAD_MAX_WAIT / 60)) minutes. Check: vastai logs $INSTANCE_ID"
  fi

  IFS=' ' read -r DL_BYTES DL_HUMAN < <(
    ssh "${SSH_OPTS[@]}" "
      b=\$(du -sb $MODEL_DIR 2>/dev/null | cut -f1 || echo 0)
      h=\$(du -sh $MODEL_DIR 2>/dev/null | cut -f1 || echo '?')
      echo \"\$b \$h\"" 2>/dev/null
  ) || { DL_BYTES=0; DL_HUMAN="?"; }
  DL_BYTES="${DL_BYTES:-0}"
  DL_HUMAN="${DL_HUMAN:-?}"

  RATE_LABEL=""
  if [[ "$DL_BYTES" -gt "$PREV_BYTES" ]] 2>/dev/null; then
    DELTA=$((DL_BYTES - PREV_BYTES))
    RATE_MBS=$((DELTA / 30 / 1048576))
    if [[ $RATE_MBS -gt 0 ]]; then
      RATE_LABEL=" ${RATE_MBS} MB/s"
    else
      RATE_KBS=$((DELTA / 30 / 1024))
      [[ $RATE_KBS -gt 0 ]] && RATE_LABEL=" ${RATE_KBS} KB/s"
    fi
  fi
  PREV_BYTES="$DL_BYTES"

  if [[ "$TOTAL_BYTES" -gt 0 ]] 2>/dev/null; then
    PCT=$((DL_BYTES * 100 / TOTAL_BYTES))
    [[ $PCT -gt 100 ]] && PCT=100
    BAR_W=30
    FILLED=$((PCT * BAR_W / 100))
    EMPTY=$((BAR_W - FILLED))
    BAR="\033[32m"
    for ((i=0; i<FILLED; i++)); do BAR+="━"; done
    if [[ $FILLED -lt $BAR_W ]]; then
      BAR+="╸\033[90m"
      for ((i=1; i<EMPTY; i++)); do BAR+="─"; done
    fi
    BAR+="\033[0m"
    printf '\r  %b %s/%s %3d%%%s %d min' "$BAR" "$DL_HUMAN" "$TOTAL_HUMAN" "$PCT" "$RATE_LABEL" "$((DOWNLOAD_ELAPSED / 60))"
  else
    printf '\r  downloaded: %s%s  %d min elapsed' "$DL_HUMAN" "$RATE_LABEL" "$((DOWNLOAD_ELAPSED / 60))"
  fi
done
printf '\r%80s\r' ""
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
