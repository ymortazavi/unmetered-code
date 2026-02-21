#!/usr/bin/env bash
# All-in-one installer for unmetered-code.
# Run: curl -sSL https://raw.githubusercontent.com/ymortazavi/unmetered-code/main/install.sh | bash
#
# This script: clones the repo, asks for config (Vast API key, etc.), provisions
# a Vast.ai instance, connects the SSH tunnel, and starts Docker. Before exiting
# it prints clear instructions on how to DESTROY the Vast instance to stop billing.

set -euo pipefail

REPO_URL="${UNMETERED_CODE_REPO:-https://github.com/ymortazavi/unmetered-code.git}"
# Use $HOME (not /$HOME); expand once so we never pass a literal $HOME path to git
DEFAULT_DIR="${UNMETERED_CODE_DIR:-$HOME/unmetered-code}"

info()  { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn()  { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }

prompt() {
  local var="$1" prompt_text="$2" default="${3:-}"
  if [[ -n "$default" ]]; then
    printf '\033[1;36m%s\033[0m [%s]: ' "$prompt_text" "$default"
    read -r "$var" < /dev/tty
    if [[ -z "${!var}" ]]; then
      printf -v "$var" '%s' "$default"
    fi
  else
    printf '\033[1;36m%s\033[0m: ' "$prompt_text"
    read -r "$var" < /dev/tty
  fi
}

yesno() {
  local prompt_text="$1" default="${2:-n}"
  local y="y/N"
  [[ "$default" =~ ^[yY] ]] && y="Y/n"
  printf '\033[1;36m%s\033[0m [%s]: ' "$prompt_text" "$y"
  read -r ans < /dev/tty
  case "${ans:-$default}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  unmetered-code — one-shot installer"
echo "  Private AI coding agents on Vast.ai (~\$1.50/hr)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# ─── Dependency checks ─────────────────────────────────

check_cmd() {
  if command -v "$1" &>/dev/null; then
    ok "$1 found"
    return 0
  else
    warn "$1 not found"
    return 1
  fi
}

missing=""
check_cmd git        || missing+=" git"
check_cmd docker     || missing+=" docker"
check_cmd python3    || missing+=" python3"
if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null 2>&1; then
  warn "docker compose (or docker-compose) not found"
  missing+=" docker-compose"
fi
if [[ -n "$missing" ]]; then
  fail "Install required tools and re-run:${missing}. See README: https://github.com/ymortazavi/unmetered-code#prerequisites"
fi

# ─── Install directory ────────────────────────────────

INSTALL_DIR=""
prompt INSTALL_DIR "Install directory" "$DEFAULT_DIR"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
# Reject bogus paths (e.g. from stdin being script when run as curl|bash); use $HOME not /$HOME
if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == *'$HOME'* || "$INSTALL_DIR" == /\$HOME* ]]; then
  INSTALL_DIR="$DEFAULT_DIR"
fi
INSTALL_DIR="$(cd -P "$(dirname "$INSTALL_DIR")" 2>/dev/null && pwd)/$(basename "$INSTALL_DIR")" || true
if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == *'$HOME'* ]]; then
  INSTALL_DIR="$DEFAULT_DIR"
fi

if [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/provision.sh" ]]; then
  if ! yesno "Directory $INSTALL_DIR already exists and looks like unmetered-code. Use it and only configure/run?" "y"; then
    fail "Aborted. Choose a different directory or remove $INSTALL_DIR and re-run."
  fi
  ok "Using existing repo at $INSTALL_DIR"
else
  if [[ -d "$INSTALL_DIR" ]]; then
    fail "Directory $INSTALL_DIR exists but is not an unmetered-code clone. Remove it or choose another path."
  fi
  info "Cloning repository into $INSTALL_DIR ..."
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" || fail "git clone failed"
  ok "Cloned into $INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ─── Config: VAST_API_KEY ──────────────────────────────

if [[ -f config.env ]] && grep -q '^VAST_API_KEY="[^"]*"' config.env 2>/dev/null; then
  current_key="$(grep '^VAST_API_KEY=' config.env 2>/dev/null | sed 's/^VAST_API_KEY="\(.*\)"$/\1/' || true)"
  if [[ -n "$current_key" && "$current_key" != "your_vast_api_key_here" ]]; then
    if yesno "config.env already has VAST_API_KEY set. Use it and skip key prompt?" "y"; then
      VAST_API_KEY="$current_key"
    fi
  fi
fi
if [[ -z "${VAST_API_KEY:-}" ]]; then
  echo
  if ! yesno "Do you have a Vast.ai account?" "y"; then
    echo
    info "Sign up and add credits here:"
    echo "  https://cloud.vast.ai/?ref_id=399895"
    echo
    info "Once you have an account, get your API key from:"
    echo "  https://cloud.vast.ai/manage-keys/"
    echo
    info "Then re-run this installer."
    exit 0
  fi
  echo
  echo "Get your API key (read/write access) from: https://cloud.vast.ai/manage-keys/"
  prompt VAST_API_KEY "Vast.ai API key" ""
  [[ -z "${VAST_API_KEY:-}" ]] && fail "VAST_API_KEY is required"
fi

# ─── Config: HF_TOKEN (optional) ──────────────────────

HF_TOKEN=""
if yesno "Do you want to set an optional HuggingFace token (faster/gated model access)?" "n"; then
  prompt HF_TOKEN "HuggingFace token (create at https://huggingface.co/settings/tokens)" ""
fi

# ─── Write config.env ─────────────────────────────────

info "Writing config.env ..."
cat > config.env <<CONFIG
# ─── Vast.ai ───────────────────────────────────────────
VAST_API_KEY="${VAST_API_KEY}"

# ─── HuggingFace (optional) ────────────────────────────
CONFIG
if [[ -n "${HF_TOKEN:-}" ]]; then
  echo "HF_TOKEN=\"${HF_TOKEN}\"" >> config.env
else
  echo "# HF_TOKEN=\"your_hf_token_here\"" >> config.env
fi
cat >> config.env <<'CONFIG'

# ─── Model (HuggingFace GGUF) ─────────────────────────
HF_REPO="unsloth/MiniMax-M2.5-GGUF"
HF_QUANT="UD-Q4_K_XL"
HF_INCLUDE="UD-Q4_K_XL/*"
MODEL_ALIAS="minimax-m2.5"

# ─── llama-server ──────────────────────────────────────
LLAMA_PORT=8080
CTX_SIZE=163840
GPU_LAYERS=-1
PARALLEL=4
KV_CACHE_TYPE="q4_0"
BATCH_SIZE=4096
UBATCH_SIZE=4096

# ─── Vast.ai Instance ─────────────────────────────────
IMAGE="vastai/llama-cpp:b8054-cuda-12.9"
DISK_GB=150
CONFIG
ok "config.env written"

# ─── vastai CLI ────────────────────────────────────────

if ! command -v vastai &>/dev/null; then
  info "Installing vastai CLI (pip install vastai) ..."
  python3 -m pip install --user vastai 2>/dev/null || pip install vastai 2>/dev/null || fail "Could not install vastai. Run: pip install vastai"
  ok "vastai installed"
fi
vastai set api-key "$VAST_API_KEY" >/dev/null 2>&1
ok "Vast.ai API key configured"

# ─── SSH key (optional) ────────────────────────────────

if yesno "Register your SSH public key with Vast.ai (needed for tunnel)?" "y"; then
  for key in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
    if [[ -f "${key/#\~/$HOME}" ]]; then
      keypath="${key/#\~/$HOME}"
      vastai set ssh-key "$(cat "$keypath")" 2>/dev/null && ok "SSH key registered" && break
    fi
  done
  if ! vastai show ssh-keys &>/dev/null; then
    warn "No SSH key found or registration failed. Create one: ssh-keygen -t ed25519 -C you@example.com"
    echo "  Then: vastai set ssh-key \"\$(cat ~/.ssh/id_ed25519.pub)\""
  fi
fi

# ─── GPU offer & provision ─────────────────────────────

echo
info "Searching for GPU offers (2× RTX Pro 6000, ~192GB VRAM)..."
echo
vastai search offers 'gpu_name in [RTX_PRO_6000_S,RTX_PRO_6000_WS] num_gpus==2 reliability>0.9' -o dph 2>/dev/null | head -15
echo
prompt OFFER_ID "Paste OFFER_ID from the table above (first column)" ""
[[ -z "${OFFER_ID:-}" ]] && fail "OFFER_ID is required to provision. Re-run and paste an ID from: vastai search offers 'gpu_name in [RTX_PRO_6000_S,RTX_PRO_6000_WS] num_gpus==2 reliability>0.9' -o dph"

info "Provisioning Vast.ai instance (this may take a few minutes)..."
./provision.sh "$OFFER_ID" || fail "provision.sh failed"

INSTANCE_ID="$(cat .instance_id 2>/dev/null || true)"
[[ -z "$INSTANCE_ID" ]] && fail "No .instance_id after provision"
ok "Instance ${INSTANCE_ID} created. View it at: https://cloud.vast.ai/instances/"

# ─── Connect (SSH tunnel + wait for model) ──────────────

info "Connecting SSH tunnel and waiting for model (5–10 min first time)..."
./connect.sh || fail "connect.sh failed"

# ─── Docker Compose ────────────────────────────────────

echo
echo "How do you want to start the local stack?"
echo "  1) Pull pre-built images (faster)"
echo "     docker compose up -d"
echo "  2) Build from source (needed for Apple Silicon / custom changes)"
echo "     docker compose -f compose.yaml -f compose.build.yaml up -d --build"
echo
prompt BUILD_CHOICE "Choose [1/2]" "1"
case "${BUILD_CHOICE}" in
  2)
    info "Building and starting local stack (this may take a few minutes on first run)..."
    docker compose -f compose.yaml -f compose.build.yaml up -d --build || fail "docker compose build failed"
    ;;
  *)
    info "Starting local stack (pulling pre-built images)..."
    docker compose up -d || fail "docker compose up failed"
    ;;
esac
ok "Stack is up"

# ─── Launch agent ─────────────────────────────────────

echo
echo "How do you want to use the agents?"
echo "  1) Terminal: OpenCode         ./opencode.sh"
echo "  2) Terminal: Claude Code      ./claude.sh"
echo "  3) Terminal: Claude (YOLO)    ./claude-yolo.sh"
echo "  4) VS Code: OpenCode          ./open-vscode.sh --opencode"
echo "  5) VS Code: Claude Code       ./open-vscode.sh --claude"
echo "  6) VS Code: Both              ./open-vscode.sh --both"
echo "  7) Skip — I'll launch manually"
echo
prompt AGENT_CHOICE "Choose [1-7]" "7"

# ─── Success + DESTROY reminder ────────────────────────

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo
printf '\033[1;31m'
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "  TO STOP BILLING — Destroy the Vast.ai instance when you're done"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "  Instance ID: ${INSTANCE_ID}"
echo ""
echo "  Destroy instance and stop charges:"
echo "    cd \"$INSTALL_DIR\" && ./destroy.sh"
echo ""
echo "  Or from anywhere:  vastai destroy instance ${INSTANCE_ID}"
echo ""
echo "  Then stop local containers:  cd \"$INSTALL_DIR\" && docker compose down"
echo "═══════════════════════════════════════════════════════════════════════"
printf '\033[0m'
echo
echo "Save the command above. You are being billed until the instance is destroyed."
echo

case "${AGENT_CHOICE}" in
  1) exec ./opencode.sh ;;
  2) exec ./claude.sh ;;
  3) exec ./claude-yolo.sh ;;
  4) exec ./open-vscode.sh --opencode ;;
  5) exec ./open-vscode.sh --claude ;;
  6) exec ./open-vscode.sh --both ;;
  *) echo "Run agents anytime:  ./opencode.sh  ./claude.sh  ./open-vscode.sh --both" ;;
esac
