#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

info()  { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <OFFER_ID>

Provision a vast.ai instance running llama-server.
API traffic is encrypted via an SSH tunnel (see connect.sh / compose.yaml).

  OFFER_ID   The offer/contract ID from 'vastai search offers'.

To find offers with 2× RTX Pro 6000 (price ascending):
  vastai search offers 'gpu_name in [RTX_PRO_6000_S,RTX_PRO_6000_WS] num_gpus==2 reliability>0.9' -o dph

Configuration is read from config.env in the same directory.
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage
OFFER_ID="$1"

source "${SCRIPT_DIR}/config.env"

[[ -z "${VAST_API_KEY:-}" ]] && fail "VAST_API_KEY is not set in config.env"

mkdir -p "${SCRIPT_DIR}/workspace"

if ! command -v vastai &>/dev/null; then
  fail "vastai CLI not found. Install: pip install vastai"
fi

vastai set api-key "$VAST_API_KEY" >/dev/null 2>&1

ONSTART=$(cat <<'ONSTART_SCRIPT'
#!/bin/bash
set -ex

export MODEL_DIR="/workspace/llama.cpp/models"

if [ ! -f "$MODEL_DIR/.download_complete" ]; then
  mkdir -p "$MODEL_DIR"

  pip install -q huggingface-hub
  HF_TK="${HF_TOKEN:-}"
  if [ -n "$HF_TK" ] && [ "$HF_TK" != "none" ]; then
    echo "Logging into HuggingFace..."
    python3 -c "from huggingface_hub import login; login(token='${HF_TK}')"
  fi
  python3 -c "
from huggingface_hub import snapshot_download
import os
token = os.environ.get('HF_TOKEN') or None
if token and token.lower() == 'none':
    token = None
snapshot_download(
    os.environ['HF_REPO'],
    allow_patterns=[os.environ['HF_INCLUDE']],
    local_dir=os.environ.get('MODEL_DIR', '/workspace/llama.cpp/models'),
    token=token,
)
"

  touch "$MODEL_DIR/.download_complete"
fi

MODEL_PATH=$(find "$MODEL_DIR" -name "*.gguf" -type f | sort | head -1)
if [ -z "$MODEL_PATH" ]; then
  echo "ERROR: No GGUF files found in $MODEL_DIR"
  exit 1
fi

LLAMA_DIR=$(dirname "$(which llama-server)")
export LD_LIBRARY_PATH="${LLAMA_DIR}:${LD_LIBRARY_PATH:-}"

echo "Starting llama-server with model: $MODEL_PATH"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
exec llama-server \
  -m "$MODEL_PATH" \
  --host 0.0.0.0 \
  --port ${LLAMA_PORT:-8080} \
  -ngl ${GPU_LAYERS:--1} \
  -c ${CTX_SIZE:-131072} \
  -np ${PARALLEL:-4} \
  --cache-type-k ${KV_CACHE_TYPE:-q4_0} \
  --cache-type-v ${KV_CACHE_TYPE:-q4_0} \
  --flash-attn on \
  -b ${BATCH_SIZE:-4096} \
  -ub ${UBATCH_SIZE:-4096} \
  --jinja \
  --metrics
ONSTART_SCRIPT
)

# No -p for llama port: it's only reachable via the SSH tunnel.
# SSH port is handled automatically by --ssh.
ENV_ARGS="-e HF_REPO=${HF_REPO}"
ENV_ARGS+=" -e HF_INCLUDE=${HF_INCLUDE}"
ENV_ARGS+=" -e HF_QUANT=${HF_QUANT}"
ENV_ARGS+=" -e LLAMA_PORT=${LLAMA_PORT}"
ENV_ARGS+=" -e CTX_SIZE=${CTX_SIZE}"
ENV_ARGS+=" -e GPU_LAYERS=${GPU_LAYERS}"
ENV_ARGS+=" -e PARALLEL=${PARALLEL}"
ENV_ARGS+=" -e KV_CACHE_TYPE=${KV_CACHE_TYPE}"
ENV_ARGS+=" -e BATCH_SIZE=${BATCH_SIZE}"
ENV_ARGS+=" -e UBATCH_SIZE=${UBATCH_SIZE}"
if [[ -n "${HF_TOKEN:-}" && "${HF_TOKEN}" != "none" ]]; then
  ENV_ARGS+=" -e HF_TOKEN=${HF_TOKEN}"
fi

info "Creating instance ${OFFER_ID} (${IMAGE}, ${DISK_GB}GB)..."

RESULT=$(vastai create instance "$OFFER_ID" \
  --image "$IMAGE" \
  --env "$ENV_ARGS" \
  --disk "$DISK_GB" \
  --onstart-cmd "$ONSTART" \
  --ssh \
  --direct \
  --raw 2>&1) || fail "Failed to create instance: ${RESULT}"

INSTANCE_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['new_contract'])" 2>/dev/null) \
  || INSTANCE_ID=$(echo "$RESULT" | grep -oE '[0-9]+' | head -1)

if [[ -z "$INSTANCE_ID" ]]; then
  fail "Could not parse instance ID from response: ${RESULT}"
fi

echo "$INSTANCE_ID" > "${SCRIPT_DIR}/.instance_id"
ok "Instance created: ${INSTANCE_ID}"
info "Waiting for instance to start..."

for i in $(seq 1 60); do
  STATUS=$(vastai show instance "$INSTANCE_ID" --raw 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('actual_status','unknown'))" 2>/dev/null \
    || echo "unknown")

  case "$STATUS" in
    running)
      ok "Instance is running"
      break
      ;;
    loading|creating|pulling)
      printf "\r  Status: %-20s (attempt %d/60)" "$STATUS" "$i"
      ;;
    exited|error)
      echo
      fail "Instance failed with status: ${STATUS}"
      ;;
    *)
      printf "\r  Status: %-20s (attempt %d/60)" "$STATUS" "$i"
      ;;
  esac
  sleep 10
done
echo

if [[ "$STATUS" != "running" ]]; then
  fail "Instance did not reach running state within 10 minutes"
fi

ok "Instance ${INSTANCE_ID} running. Model will download next (5–10 min)."
echo
